module PortfolioInsights
  class Analyzer < ApplicationService
    MAX_WORDS = 350
    CACHE_TTL = 60.seconds # LTP cache window
    BATCH_SIZE  = 25 # Dhan bulk-quote limit
    MAX_RETRIES = 3

    attr_reader :interactive

    def initialize(dhan_holdings:, dhan_balance: nil, interactive: false)
      @raw    = dhan_holdings.deep_dup
      @cash   = dhan_balance || Dhanhq::API::Funds.balance[:availabelBalance]
      @interactive = interactive
    end

    def call
      enrich_with_ltp!(@raw)
      snapshot = build_snapshot(@raw)
      prompt   = build_prompt(snapshot)

      Openai::ChatRouter.ask!(
        prompt,
        system: SYSTEM_SEED,
        temperature: 0.35
      )
      # notify(answer, tag: 'PORTFOLIO_AI') if interactive
      # answer
    rescue StandardError => e
      log_error(e.message)
      notify("❌ Portfolio AI failed: #{e.message}", tag: 'PORTFOLIO_AI_ERR')
      nil
    end

    # --------------------------------------------------------------------
    private

    SYSTEM_SEED = <<~SYS.freeze
      You are an Indian equity portfolio expert.
      • Clearly identify equity instruments and trade types (Delivery, Intraday).
      • State exact cash balance and impact on actionable suggestions.
      • Bullet style, concise ≤ #{MAX_WORDS} words.
      • Headings with emojis (👉🚀🐢⚠️💡).
      • Include precise allocation, risks (sector concentration, liquidity), and clear actions.
      • Finish clearly with “— end of brief”.
    SYS

    # ---------- NEW: pull spot prices ---------------------------------
    #
    # Tries three fall-backs, in this order:
    #   1. Instrument cache (db column :ltp if you store it)
    #   2. Dhan Market Quote endpoint         (fast)
    #   3. NSE price snapshot via Instrument#ltp (your wrapper)  (slow)
    #
    # ---------- LTP hydrator (batched & cached) -------------------------
    def enrich_with_ltp!(rows)
      # Group securityIds by exchangeSegment for batch API call
      segments = Hash.new { |h, k| h[k] = [] }

      rows.each do |h|
        segment = h['exchangeSegment'] || 'NSE_EQ'
        segments[segment] << h['securityId'].to_i
      end

      begin
        ltp_data = Dhanhq::API::MarketFeed.ltp(segments)

        rows.each do |h|
          segment = h['exchangeSegment'] || 'NSE_EQ'
          sec_id = h['securityId'].to_s

          h['ltp'] = ltp_data.dig('data', segment, sec_id, 'last_price').to_f
        end
      rescue StandardError => e
        Rails.logger.error "[Analyzer] ❌ Batch LTP fetch failed: #{e.class} - #{e.message}"
        # fallback (optional): set to 0 or try single fetch per item
        rows.each { |h| h['ltp'] ||= 0.0 }
      end
    end

    def fetch_bulk_quotes(sec_ids)
      return {} if sec_ids.empty?

      results = {}
      sec_ids.each_slice(BATCH_SIZE) do |slice|
        retries = 0
        begin
          resp = Dhanhq::API::Market.bulk_quote(securityIds: slice) # ← helper below
          slice.each do |id|
            ltp = resp[id.to_s]&.dig('lastPrice').to_f
            results[id.to_s] = ltp.positive? ? ltp : 0
          end
        rescue StandardError => e
          retries += 1
          raise if retries > MAX_RETRIES

          sleep(e.retry_after || 0.8)
          retry
        rescue StandardError => e
          log_warn("Quote batch failed (#{slice.inspect}): #{e.message}")
          slice.each { |id| results[id.to_s] = 0 }
        end
      end
      results
    end

    # tiny helper used twice
    def cache_key(sec_id) = "ltp:#{sec_id}"

    # ---------- snapshot --------------------------------------------------
    # ---------- snapshot ----------------------------------------------
    def build_snapshot(rows)
      rows.each do |h|
        h['quantity']     = (h['totalQty'] || h['availableQty']).to_f
        h['averagePrice'] = h['avgCostPrice'].to_f
        h['pnl']          = (h['ltp'] - h['averagePrice']) * h['quantity']
      end

      total_equity = rows.sum { |h| h['ltp'] * h['quantity'] }
      total_equity = 1 if total_equity.zero?

      rows.each { |h| h['weight_pct'] = 100.0 * (h['ltp'] * h['quantity']) / total_equity }

      { holdings: rows, cash: @cash || 0.0, total: total_equity }
    end

    # ---------- prompt ----------------------------------------------------
    # ---------- Prompt builder -----------------------------------------
    def build_prompt(snap)
      money = ->(v) { "₹#{format('%.2f', v)}" }

      holdings_lines = snap[:holdings].sort_by { |h| -h['weight_pct'] }.map do |h|
        pnl_pct = if h['averagePrice'].zero?
                    0.0
                  else
                    100 * (h['ltp'] - h['averagePrice']) / h['averagePrice']
                  end
        [
          "• #{h['tradingSymbol'].ljust(12)}",
          "Type: #{h['instrumentType'] || 'Equity'}",
          "Trade: #{h['tradeType'] || 'Delivery'}",
          "Qty: #{h['quantity'].to_i}",
          "Avg: #{money[h['averagePrice']]}",
          "LTP: #{money[h['ltp']]}",
          "PnL: #{money[h['pnl']]} (#{format('%.1f', pnl_pct)}%)",
          "Wt: #{format('%.1f', h['weight_pct'])}%"
        ].join(' | ')
      end.join("\n")

      <<~PROMPT
        👉 CASH AVAILABLE: #{money[snap[:cash]]}

        🚀 CURRENT HOLDINGS:
        #{holdings_lines}

        Please explicitly provide:
        1️⃣ Best & worst performers clearly (PnL %).
        2️⃣ Sector allocation (>5% buckets).
        3️⃣ Explicit risks: single-stock concentration (>25%), high beta, illiquid stocks.
        4️⃣ Actionable recommendations clearly referencing cash available (trim, average, add, hedge).
      PROMPT
    end
  end
end
