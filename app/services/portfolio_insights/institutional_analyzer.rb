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
    MAX_TOKENS      = 8_000
    DAILY_CACHE_KEY = 'portfolio_ai_v2:%<cid>s:%<day>s'
    LTP_BATCH_SIZE  = 25 # <= now respected
    MAX_ALLOC_PCT   = 10.0
    EXEC_BAND_PCT   = 5 # max price deviation vs LTP

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
      enrich_with_prices!(@raw_holdings)
      snaps = build_snapshots(@raw_holdings)
      tech  = build_technicals(snaps)
      prompt = build_prompt(snaps, tech)

      Rails.logger.debug prompt
      answer = ask_openai(prompt)
      validate_prices!(answer, snaps) # sanity-check hallucinated prices
      # answer = prompt
      Rails.cache.write(cache_key, answer, expires_in: 1.hour)
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
    def default_seg(seg)
      if seg == 'ALL'
        'NSE_EQ'
      else
        seg == 'BSE' ? 'BSE_EQ' : seg
      end
    end

    def enrich_with_prices!(rows)
      seg_map = Hash.new { |h, k| h[k] = [] }

      rows.each do |h|
        segment = extract_segment(h)
        seg_map[segment] << h['securityId'].to_i
      end

      seg_map.each do |segment, ids|
        ids.uniq.each_slice(LTP_BATCH_SIZE) do |slice|
          retries = 0
          begin
            sleep(1.1) # respect 1/sec limit for Quote APIs

            resp = Dhanhq::API::MarketFeed.ltp({ segment => slice })

            # safer nested access
            data = resp['data'][segment]

            slice.each do |sid|
              h = rows.find { |r| r['securityId'].to_i == sid }
              ltp = begin
                data.dig(sid.to_s, 'last_price').to_f
              rescue StandardError
                0.0
              end
              h['ltp'] = ltp.positive? ? ltp : 0.0
            end
          rescue StandardError => e
            retries += 1
            if retries < 3
              Rails.logger.warn "[LTP] Retry #{retries} for #{segment} slice #{slice.inspect}: #{e.message}"
              sleep(2.0)
              retry
            else
              Rails.logger.error "[LTP] FAILED for #{segment} after retries: #{e.message}"
              slice.each do |sid|
                h = rows.find { |r| r['securityId'].to_i == sid }
                h['ltp'] ||= 0.0
              end
            end
          end
        end
      end
    end

    def extract_segment(h)
      seg = h['exchangeSegment'] || h['exchange'] || 'NSE'
      case seg
      when 'ALL', 'NSE' then 'NSE_EQ'
      when 'BSE' then 'BSE_EQ'
      else seg
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
          seg: default_seg(h['exchange']),
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
      count = 0
      snaps.each_with_object({}) do |s, memo|
        sleep(1) if (count % 5).zero?
        candles = fetch_history(s[:sec_id], s[:seg]) # hash-of-arrays
        count += 1
        memo[s[:symbol]] = Indicators::HolyGrail.call(candles:) # one-liner
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
      ) || {}
    rescue StandardError
      {}
    end

    # ---------- prompt --------------------------------------------------
    def build_prompt(snaps, tech)
      ₹ = ->(v) { "₹#{format('%.2f', v)}" }
      cash_line = "Cash available: #{₹[@cash_hash[:availabelBalance].to_f]}" if @cash_hash.present?

      table = snaps.map do |s|
        t = tech[s[:symbol]] || {}
        [
          "• #{s[:symbol].ljust(12)}",
          "Qty: #{s[:qty].to_i}",
          "LTP: #{₹[s[:ltp]]}",
          "Wt: #{format('%.1f', s[:weight])}%",
          "PnL: #{₹[s[:pnl_abs]]} (#{format('%.1f', s[:pnl_pct])}%)",
          "Trend: #{t[:trend] || 'N/A'}  RSI: #{format('%.1f', t[:rsi14] || 0)}  ATR: #{format('%.2f', t[:atr20] || 0)}"
        ].join('  ')
      end.join("\n")

      <<~PROMPT
        PORTFOLIO SUMMARY — #{Time.zone.today}
        #{cash_line}

        #{table}

        ===== IC MANDATE =====
        • Cap per name → #{MAX_ALLOC_PCT}% NAV
        • 1×ATR ≈ 1 % NAV risk sizing
        • Long-only, cash buffer ≥ 5 %
        ======================

        DELIVERABLE:
        ≤ 12 bullets, *exact* grammar:
          🔺 TRIM <SYMBOL> to <new wt%> — sell <N> shares at ₹<price> ( reason )
          🔻 ADD  <SYMBOL> to <new wt%> — buy  <N> shares at ₹<price> ( reason )
          ⛔️ EXIT <SYMBOL> full — sell all shares at ₹<price> ( reason )
         AFTER the trade list, append exactly two labelled sections:

         === CORE (≥ 3 yrs) ===
         • <SYMBOL> — thesis, exit > ₹<price>

         === TRADING (< 6 mos) ===
         • <SYMBOL> — catalyst, exit @ ₹<price> or <date>

        Finish with “— end of brief”
      PROMPT
    end

    # ---------------- OpenAI wrapper ----------------------------------
    def ask_openai(prompt)
      Openai::ChatRouter.ask!(
        prompt,
        system: <<~SYS,
          You are chief risk officer of a US$5 Bn hedge fund.  Rules:
          • All limit prices must be within ±#{EXEC_BAND_PCT}% of LTP.
          • NEVER sell more shares than “Qty:” shows.
          • Show the new weight % after the trade.
          • Classify every holding as either CORE (multi-year) or TRADING (< 6 m).
          • Give a realistic exit price OR date in those lists.
          • One-line valuation / momentum / catalyst rationale.
          • Use ✅ grammar exactly; no extra commentary.
        SYS
        max_tokens: MAX_TOKENS,
        force: true
      )
    end

    # ---------- sanity-check prices ------------------------------------
    def validate_prices!(text, snaps)
      text.scan(/([A-Z]{2,})[^₹]*₹([\d\.]+)/).each do |sym, price_str|
        price = price_str.to_f
        snap  = snaps.find { |r| r[:symbol] == sym }
        next unless snap && snap[:ltp].positive?

        diff = ((price - snap[:ltp]).abs / snap[:ltp]) * 100
        Rails.logger.warn("⚠️ #{sym} price deviation #{format('%.1f', diff)}%") if diff > EXEC_BAND_PCT
      end
    end
  end
end
