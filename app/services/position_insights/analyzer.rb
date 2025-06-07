# frozen_string_literal: true

module PositionInsights
  class Analyzer < ApplicationService
    MAX_WORDS   = 250
    BATCH_SIZE  = 25

    def initialize(dhan_positions:, cash_balance: nil, interactive: false)
      @raw_positions = dhan_positions.deep_dup
      @cash = cash_balance || Dhanhq::API::Funds.balance[:availabelBalance]
      @interactive = interactive
    end

    def call
      enrich_positions_with_ltp_and_spot!(@raw_positions)
      normalized = normalize(@raw_positions)
      prompt = build_prompt(normalized)
      answer = Openai::ChatRouter.ask!(
        prompt,
        system: SYSTEM_SEED,
        temperature: 0.3
      )

      notify(answer, tag: 'POSITIONS_AI') if @interactive
      answer
    rescue StandardError => e
      log_error(e.message)
      notify("❌ Positions AI failed: #{e.message}", tag: 'POSITIONS_AI_ERR')
      nil
    end

    private

    SYSTEM_SEED = <<~SYS.freeze
      You are an Indian market trading assistant.
      • Identify positions (CE, PE, Futures, Equity: Intraday/Normal).
      • Assess risks explicitly using Greeks (Delta, Gamma, Theta).
      • Consider underlying (NIFTY/BANKNIFTY).
      • Mention margin implications & cash balance.
      • Provide actionable hedging/exit suggestions.
      • Bullet points, concise ≤ #{MAX_WORDS} words.
      • Emojis in headings (👉⚠️💡📉📈).
      • Conclude clearly with “— end of brief”.
    SYS

    INDEX_MAP = { 'NIFTY' => 13, 'BANKNIFTY' => 25 }

    def enrich_positions_with_ltp_and_spot!(rows)
      segments = Hash.new { |h, k| h[k] = [] }

      rows.each do |pos|
        segment = pos['exchangeSegment'] || 'NSE_FNO'
        segments[segment] << pos['securityId'].to_i

        index_name = pos['tradingSymbol'][/^(NIFTY|BANKNIFTY)/]
        segments['IDX_I'] << INDEX_MAP[index_name] if INDEX_MAP[index_name]
      end

      segments.each { |_, ids| ids.uniq! }

      ltp_data = Dhanhq::API::MarketFeed.ltp(segments)

      rows.each do |pos|
        segment = pos['exchangeSegment'] || 'NSE_FNO'
        sec_id = pos['securityId'].to_s
        pos['lastTradedPrice'] = ltp_data.dig('data', segment, sec_id, 'last_price').to_f

        index_name = pos['tradingSymbol'][/^(NIFTY|BANKNIFTY)/]
        if INDEX_MAP[index_name]
          idx_id = INDEX_MAP[index_name].to_s
          pos['underlying_spot'] = ltp_data.dig('data', 'IDX_I', idx_id, 'last_price').to_f
        end
      end
    rescue StandardError => e
      Rails.logger.error "[PositionInsights::Analyzer] ❌ LTP & Spot fetch failed: #{e.class} - #{e.message}"
      rows.each { |pos| pos['lastTradedPrice'] ||= 0.0 }
    end

    def normalize(raw)
      raw.map do |p|
        qty = p['netQty'].to_f
        avg = (p['costPrice'] || p['averagePrice'] || p['buyAvg'] || 0).to_f
        ltp = p['lastTradedPrice'].to_f
        pnl = (p['unrealizedProfit'] || ((ltp - avg) * qty)).to_f

        pnl_pct = avg.zero? || qty.zero? ? 0 : (pnl / (avg * qty)) * 100

        type = p['drvOptionType'] ? "#{p['drvOptionType']}#{p['drvStrikePrice']}" : 'Equity/Futures'

        {
          symbol: p['tradingSymbol'],
          qty: qty,
          avg: avg,
          ltp: ltp,
          pnl: pnl,
          pnl_pct: pnl_pct,
          opt: type.strip,
          expiry: p['drvExpiryDate'],
          underlying_spot: p['underlying_spot'],
          trade_type: p['positionType'] || 'Normal'
        }
      end
    end

    def infer_ltp(avg, qty, u_pnl)
      return 0 if qty.zero? || u_pnl.nil?

      avg + (u_pnl.to_f / qty)
    end

    def build_prompt(rows)
      money = ->(v) { "₹#{format('%.2f', v)}" }

      positions = rows.map do |r|
        [
          "• #{r[:symbol].ljust(18)}",
          "Type: #{r[:opt]}",
          "Trade: #{r[:trade_type]}",
          "Expiry: #{r[:expiry] || 'NA'}",
          "Qty: #{r[:qty]}",
          "Avg: #{money[r[:avg]]}",
          "LTP: #{money[r[:ltp]]}",
          "PnL: #{money[r[:pnl]]} (#{format('%.2f', r[:pnl_pct])}%)",
          ("Spot: #{money[r[:underlying_spot]]}" if r[:underlying_spot])
        ].compact.join(' | ')
      end.join("\n")

      <<~PROMPT
        👉 AVAILABLE CASH: #{money[@cash]}

        📈📉 POSITIONS:
        #{positions}

        Analyze clearly:
        1️⃣ Clearly state winners & losers (negative PnL% means loss).
        2️⃣ Explicit margin/theta risks, considering balance & underlying.
        3️⃣ Hedging/exit advice (Delta, Gamma, Theta).
      PROMPT
    end
  end
end
