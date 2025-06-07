# frozen_string_literal: true

module PositionInsights
  class Analyzer < ApplicationService
    MAX_WORDS   = 250
    CACHE_TTL   = 60.seconds
    BATCH_SIZE  = 25
    MAX_RETRIES = 3

    attr_reader :interactive

    def initialize(dhan_positions:, interactive: false)
      @raw_positions = dhan_positions.deep_dup
      @interactive = interactive
    end

    def call
      enrich_with_ltp!(@raw_positions)
      normalized = normalize(@raw_positions)
      prompt = build_prompt(normalized)

      answer = Openai::ChatRouter.ask!(
        prompt,
        system: SYSTEM_SEED,
        temperature: 0.3
      )

      notify(answer, tag: 'POSITIONS_AI') if interactive
      answer
    rescue StandardError => e
      log_error(e.message)
      notify("❌ Positions AI failed: #{e.message}", tag: 'POSITIONS_AI_ERR')
      nil
    end

    # --------------------------------------------------------------------
    private

    SYSTEM_SEED = <<~SYS.freeze
      You are an Indian F&O trader’s assistant.
      • Explicitly identify positions by type (CE, PE, Futures, Intraday/Normal).
      • Clearly assess risk using Greeks (Delta, Gamma, Theta).
      • State precise margin considerations given current cash balance.
      • Provide targeted exit/hedging recommendations considering option expiry and market conditions.
      • Bullet style concise ≤ #{MAX_WORDS} words.
      • Headings with emojis (👉⚠️💡📉📈).
      • Clearly conclude with “— end of brief”.
    SYS

    # ---------- LTP hydration --------------------------------------------
    def enrich_with_ltp!(rows)
      segments = Hash.new { |h, k| h[k] = [] }

      rows.each do |pos|
        segment = pos['exchangeSegment'] || 'NSE_FNO'
        segments[segment] << pos['securityId'].to_i
      end

      begin
        ltp_data = Dhanhq::API::MarketFeed.ltp(segments)

        rows.each do |pos|
          segment = pos['exchangeSegment'] || 'NSE_FNO'
          sec_id  = pos['securityId'].to_s
          ltp     = ltp_data.dig('data', segment, sec_id, 'last_price')
          pos['lastTradedPrice'] = ltp.to_f if ltp
        end
      rescue StandardError => e
        Rails.logger.error "[PositionInsights::Analyzer] ❌ Batch LTP fetch failed: #{e.class} - #{e.message}"
        rows.each { |pos| pos['lastTradedPrice'] ||= 0.0 }
      end
    end

    # ---------- Normalizer -----------------------------------------------
    def normalize(raw)
      raw.map do |p|
        qty  = p['netQty'].to_f
        avg  = (p['averagePrice'] || p['buyAvg'] || 0).to_f
        ltp  = (p['lastTradedPrice'] || p['costPrice'] ||
               infer_ltp(avg, qty, p['unrealizedProfit'])).to_f
        pnl  = (p['pl'] || p['unrealizedProfit'] ||
               ((ltp - avg) * qty)).to_f

        {
          symbol: p['tradingSymbol'],
          qty: qty,
          avg: avg,
          ltp: ltp,
          pnl: pnl,
          opt: "#{p['drvOptionType']}#{p['drvStrikePrice']}".strip,
          expiry: p['drvExpiryDate']
        }
      end
    end

    def infer_ltp(avg, qty, u_pnl)
      return 0 if qty.zero? || u_pnl.nil?

      avg + (u_pnl.to_f / qty)
    end

    # ---------- Prompt builder -------------------------------------------
    def build_prompt(rows)
      ₹ = ->(v) { "₹#{'%.2f' % v}" }

      table = rows.map do |r|
        type = r[:opt].empty? ? 'Futures/Equity' : r[:opt]
        trade_type = r[:tradeType] || 'Normal'

        [
          "• #{r[:symbol].ljust(18)}",
          "Type: #{type}",
          "Trade: #{trade_type}",
          "Expiry: #{r[:expiry]}",
          "Qty: #{r[:qty]}",
          "Avg: #{₹[r[:avg]]}",
          "LTP: #{₹[r[:ltp]]}",
          "PnL: #{₹[r[:pnl]]}"
        ].join(' | ')
      end.join("\n")

      <<~PROMPT
        👉 AVAILABLE CASH BALANCE: #{₹[@cash || 0.0]}

        📈📉 CURRENT POSITIONS:
        #{table}

        Provide precise analysis:
        1️⃣ Clearly state top risk-weighted winners & losers (with exact PnL%).
        2️⃣ Explicit margin/theta risks given position types, expiry, and balance.
        3️⃣ Precise hedging or exit recommendations based on Delta, Gamma, and Theta.
      PROMPT
    end
  end
end
