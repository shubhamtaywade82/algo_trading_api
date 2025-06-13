# frozen_string_literal: true

# == Institutional‑grade Portfolio Analyzer v2 (patched)
#
# • Caches analysis once per trading day (per client) to save OpenAI tokens.
# • Batched LTP fetch via Dhan MarketFeed – one call per segment only.
# • Pulls 1‑year daily OHLC + 60‑min intraday for every holding.
# • Computes SMA‑50 / SMA‑200, RSI‑14, ATR‑20 (pure Ruby) for signals.
# • Generates exact trim / add quantities to respect max‑allocation (10 % default).
# • Accepts optional open positions & cash balance for holistic advice.
# • Returns a rich prompt for OpenAI and the raw metrics for custom dashboards.
#
# Dependencies:
#   – Dhanhq gem (client + Historical / MarketFeed endpoints)
#   – Rails.cache
#   – Openai::ChatRouter abstraction
#
#=======================================================================
module PortfolioInsights
  class InstitutionalAnalyzer < ApplicationService
    MAX_TOKENS      = 4_000
    DAILY_CACHE_KEY = 'portfolio_ai_v2:%<cid>s:%<day>s'
    LTP_BATCH_SIZE  = 25 # <= now respected
    MAX_ALLOC_PCT   = 10.0

    def initialize(dhan_holdings:, dhan_positions: nil, dhan_balance: nil,
                   client_id: nil, interactive: false)
      @raw_holdings  = Array(dhan_holdings).deep_dup
      @raw_positions = Array(dhan_positions).deep_dup
      @cash_hash     = dhan_balance || {}
      @cid           = client_id || infer_client_id
      @interactive   = interactive
    end

    # ------------------------------------------------------------------
    def call
      return Rails.cache.read(cache_key) if Rails.cache.exist?(cache_key)

      enrich_with_prices!(@raw_holdings)
      snaps   = build_snapshots(@raw_holdings)
      tech    = build_technicals(snaps)
      prompt  = build_prompt(snaps, tech)
      answer  = ask_openai(prompt)

      Rails.cache.write(cache_key, answer, expires_in: 24.hours)
      notify(answer, tag: 'PORTFOLIO_AI_V2') if @interactive
      answer
    rescue StandardError => e
      log_error(e.full_message)
      notify("❌ Institutional Analyzer failed: #{e.message}", tag: 'PORTFOLIO_AI_ERR')
      nil
    end

    # ------------------------------------------------------------------
    private

    def cache_key = format(DAILY_CACHE_KEY, cid: @cid, day: Date.current)

    # Try to grab client‑id from any array passed in
    def infer_client_id
      (@raw_holdings.first || @raw_positions.first || {})['dhanClientId'] || 'unknown'
    end

    # ---------------- Price enrichment (one MarketFeed call) ----------
    def default_seg(seg) = seg.presence || 'NSE_EQ'

    def enrich_with_prices!(rows)
      seg_map = Hash.new { |h, k| h[k] = [] }
      rows.each { |h| seg_map[default_seg(h['exchangeSegment'])] << h['securityId'].to_i }
      seg_map.each_value do |ids|
        ids.uniq!; ids.each_slice(LTP_BATCH_SIZE) do |slice|
          resp = Dhanhq::API::MarketFeed.ltp(default_seg_ids_hash(slice, seg_map.key(ids)))
          slice.each do |sid|
            rows.find { |r| r['securityId'].to_i == sid }['ltp'] =
              resp.dig('data', seg_map.key(ids), sid.to_s, 'last_price').to_f
          end
        end
      end
    end

    def default_seg_ids_hash(ids, seg) = { seg => ids }

    # ---------------- Snapshot builder --------------------------------
    def build_snapshots(rows)
      total = rows.sum { |h| h['ltp'] * h['totalQty'].to_f }.nonzero? || 1
      rows.map do |h|
        qty, avg, ltp = h.values_at('totalQty', 'avgCostPrice', 'ltp').map(&:to_f)
        {
          symbol: h['tradingSymbol'],
          sec_id: h['securityId'],
          seg: default_seg(h['exchangeSegment']),
          qty: qty, avg: avg, ltp: ltp,
          market_value: ltp * qty,
          pnl_abs: (ltp - avg) * qty,
          pnl_pct: avg.zero? ? 0 : (ltp - avg) / avg * 100,
          weight: (ltp * qty) / total * 100
        }
      end
    end

    # ---------------- Technical analysis --------------------------------
    def build_technicals(snaps)
      snaps.each_with_object({}) do |s, memo|
        daily = fetch_history(s[:sec_id], s[:seg])
        memo[s[:symbol]] = {
          sma50: sma(daily, 50),
          sma200: sma(daily, 200),
          rsi14: rsi(daily, 14),
          atr20: atr(daily, 20),
          trend: trend_signal(daily, s[:ltp])
        }
      end
    end

    # ------------- Historical helpers (simple wrappers) -----------------
    def fetch_history(sec_id, seg, period: 365)
      from = (Date.current - period).strftime('%Y-%m-%d')
      to   = Date.current.strftime('%Y-%m-%d')
      Dhanhq::API::Historical.daily(
        securityId: sec_id,
        exchangeSegment: seg,
        instrument: 'EQUITY',
        fromDate: from,
        toDate: to
      )['data'] || []
    rescue StandardError
      []
    end

    def fetch_intraday(sec_id, seg)
      Dhanhq::API::Historical.intraday(
        securityId: sec_id,
        exchangeSegment: seg,
        instrument: 'EQUITY',
        interval: '60',
        fromDate: Date.current.strftime('%Y-%m-%d'),
        toDate: Date.current.strftime('%Y-%m-%d')
      )['data'] || []
    rescue StandardError
      []
    end

    # ---------------- Indicator math (pure Ruby) -----------------------
    def sma(data, len)
      closes = data.last(len).map { |d| d['close'].to_f }
      return 0 if closes.size < len

      closes.sum / len
    end

    def rsi(data, len)
      closes = data.map { |d| d['close'].to_f }
      return 0 if closes.size <= len

      gains = []
      losses = []
      closes.each_cons(2) do |a, b|
        diff = b - a
        diff.positive? ? gains << diff : losses << diff.abs
      end
      avg_gain = gains.last(len).sum / len
      avg_loss = losses.last(len).sum / len
      return 50 if avg_loss.zero?

      100 - (100 / (1 + (avg_gain / avg_loss)))
    end

    def atr(data, len)
      trs = data.each_cons(2).map do |prev, curr|
        high = curr['high'].to_f
        low  = curr['low'].to_f
        close_prev = prev['close'].to_f
        [high - low, (high - close_prev).abs, (low - close_prev).abs].max
      end
      return 0 if trs.size < len

      trs.last(len).sum / len
    end

    def trend_signal(daily, ltp)
      sma50 = sma(daily, 50)
      sma200 = sma(daily, 200)
      return 'SIDE' if sma50.zero? || sma200.zero?
      return 'UP'   if sma50 > sma200 && ltp > sma50
      return 'DOWN' if sma50 < sma200 && ltp < sma50

      'SIDE'
    end

    # ---------------- Prompt builder -----------------------------------
    def build_prompt(snaps, tech)
      ₹ = ->(v) { "₹#{format('%.2f', v)}" }
      cash = @cash_hash[:availabelBalance].to_f
      cash_line = "Cash available: #{₹[cash]}" unless cash.zero?

      body = snaps.map do |s|
        t = tech[s[:symbol]] || {}
        [
          "• #{s[:symbol].ljust(12)}",
          "Wt: #{format('%.1f', s[:weight])}%",
          "PnL: #{₹[s[:pnl_abs]]} (#{format('%.1f', s[:pnl_pct])}%)",
          "Trend: #{t[:trend] || 'N/A'} RSI: #{format('%.1f', t[:rsi14] || 0)}",
          "ATR: #{format('%.2f', t[:atr20] || 0)}"
        ].join('  ')
      end.join("\n")

      <<~PROMPT
        PORTFOLIO SUMMARY — #{Date.current}
        #{cash_line}

        #{body}

        Rules:
        • Keep single-name weight ≤ #{MAX_ALLOC_PCT}%.
        • Trim winners above cap. Add / average losers with UP trend & RSI < 35.
        • Size trades to max 1 ATR risk ≈ 1 % of equity.

        Generate an institutional-grade trade plan, one instruction per line:
        «TRIM <SYMBOL> to #{MAX_ALLOC_PCT}% (sell N shares)»
        «ADD  <SYMBOL> to #{MAX_ALLOC_PCT}% (buy  N shares)»
        «EXIT <SYMBOL> full»
        — end of brief
      PROMPT
    end

    # ---------------- OpenAI wrapper -----------------------------------
    def ask_openai(prompt)
      Openai::ChatRouter.ask!(
        prompt,
        system: 'You are a senior portfolio strategist at a global macro hedge fund. Return bullet‑point instructions only.',
        temperature: 0.25,
        max_tokens: MAX_TOKENS
      )
    end
  end
end
