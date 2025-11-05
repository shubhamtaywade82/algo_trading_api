# frozen_string_literal: true

module PositionInsights
  class Analyzer < ApplicationService
    MAX_WORDS   = 350
    BATCH_SIZE  = 25

    def initialize(dhan_positions:, cash_balance: nil, interactive: false)
      @raw_positions = dhan_positions.deep_dup
      @cash = cash_balance || DhanHQ::Models::Funds.fetch.available_balance.to_f
      @interactive = interactive
    end

    def call
      if @raw_positions.empty?
        notify('No  open positions found', tag: 'POSITIONS_AI')
        return
      end
      enrich_positions_with_ltp_and_spot!(@raw_positions)
      normalized = normalize(@raw_positions)
      prompt = build_prompt(normalized)

      answer = Openai::ChatRouter.ask!(
        prompt,
        system: SYSTEM_SEED
      )

      notify(answer, tag: 'POSITIONS_AI') if @interactive
    rescue StandardError => e
      log_error(e.message)
      notify("❌ Positions AI failed: #{e.message}", tag: 'POSITIONS_AI_ERR')
      nil
    end

    private

    SYSTEM_SEED = <<~SYS.freeze
      You are an Indian market trading assistant.
      • Identify instruments as Equity (Delivery/Intraday), F&O (CE/PE/FUT), Commodity, Currency.
      • Include exchange, product type & expiry where applicable.
      • Assess risks using Greeks (Delta, Gamma, Theta) for options.
      • Show winners & losers across all positions (Equity + F&O) based on PnL% even for small PnL.
      • Consider underlying (NIFTY/BANKNIFTY).
      • Mention margin/cash balance & drawdown exposure.
      • Provide actionable hedging or exit advice.
      • Bullet style ≤ #{MAX_WORDS} words.
      • Emojis in headings (👉⚠️💡📉📈).
      • Conclude clearly with “— end of brief”.
    SYS

    INDEX_MAP = { 'NIFTY' => 13, 'BANKNIFTY' => 25 }.freeze

    def enrich_positions_with_ltp_and_spot!(rows)
      segments = Hash.new { |h, k| h[k] = [] }

      rows.each do |pos|
        segment = pos['exchangeSegment'] || 'NSE_FNO'
        segments[segment] << pos['securityId'].to_i

        index_name = pos['tradingSymbol'][/^(NIFTY|BANKNIFTY)/]
        segments['IDX_I'] << INDEX_MAP[index_name] if INDEX_MAP[index_name]
      end

      segments.each_value(&:uniq!)

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
        buy_qty = p['buyQty'].to_f
        avg = (p['costPrice'] || p['averagePrice'] || p['buyAvg'] || 0).to_f
        ltp = p['lastTradedPrice'].to_f

        pnl, pnl_pct =
          if p['positionType'] == 'CLOSED'
            realized = p['realizedProfit'].to_f
            pnl_pct = buy_qty.zero? ? 0 : (realized / (avg * buy_qty)) * 100
            [realized, pnl_pct]
          else
            unrealized = (p['unrealizedProfit'] || ((ltp - avg) * qty)).to_f
            pnl_pct = avg.zero? || qty.zero? ? 0 : (unrealized / (avg * qty)) * 100
            [unrealized, pnl_pct]
          end

        instrument_type = infer_instrument_type(p)

        {
          symbol: p['tradingSymbol'],
          exchange: p['exchangeSegment'],
          product: p['productType'] || 'Unknown',
          position_type: p['positionType'],
          qty: qty,
          avg: avg,
          ltp: ltp,
          pnl: pnl,
          pnl_pct: pnl_pct,
          instrument_type: instrument_type,
          expiry: p['drvExpiryDate'],
          strike: p['drvStrikePrice'].to_f,
          option_type: p['drvOptionType'],
          underlying_spot: p['underlying_spot']
        }
      end
    end

    def infer_instrument_type(p)
      if p['exchangeSegment'] == 'NSE_EQ' || p['exchangeSegment'] == 'BSE_EQ'
        'Equity'
      elsif p['exchangeSegment'] == 'MCX_COMM'
        'Commodity'
      elsif p['exchangeSegment'].include?('CURRENCY')
        'Currency'
      elsif p['drvOptionType']
        "#{p['drvOptionType']} #{p['drvStrikePrice']}".strip
      else
        'Futures'
      end
    end

    def build_prompt(rows)
      money = ->(v) { "₹#{format('%.2f', v)}" }

      positions = rows.map do |r|
        [
          "• #{r[:symbol]} (#{r[:instrument_type]}) [#{r[:position_type]}]",
          "Exch: #{r[:exchange]}",
          "Prod: #{r[:product]}",
          ("Expiry: #{r[:expiry]}" if r[:expiry] && r[:expiry] != '0001-01-01'),
          ("Strike: #{r[:strike]}" if (r[:strike]).positive?),
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
        1️⃣ State winners & losers based on PnL%.
        2️⃣ Include margin, theta risks, Greeks (Delta/Gamma/Theta) for options.
        3️⃣ Provide specific hedging/exit recommendations.
      PROMPT
    end
  end
end
