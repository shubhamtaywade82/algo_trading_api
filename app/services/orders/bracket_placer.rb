# frozen_string_literal: true

module Orders
  class BracketPlacer < ApplicationService
    def call
      Positions::ActiveCache.all_positions.each do |pos|
        process_position(pos)
      rescue StandardError => e
        log_error("Error for #{pos['tradingSymbol']}: #{e.class} - #{e.message}")
      end
    end

    private

    def process_position(pos)
      return if bracket_order_exists?(pos)

      entry_price = PriceMath.round_tick(pos['costPrice'].to_f)
      instrument_type = detect_instrument_type(pos)

      sl_pct = instrument_type == :option ? 25.0 : 10.0
      tp_pct = instrument_type == :option ? 50.0 : 20.0

      sl_val = PriceMath.round_tick(entry_price * sl_pct / 100.0)
      tp_val = PriceMath.round_tick(entry_price * tp_pct / 100.0)

      payload = {
        securityId: pos['securityId'],
        transactionType: pos['netQty'].to_f.positive? ? 'SELL' : 'BUY',
        orderType: 'MARKET',
        quantity: pos['netQty'].abs,
        exchangeSegment: pos['exchangeSegment'],
        productType: pos['productType'],
        validity: 'DAY',
        price: pos['ltp'] || pos['buyAvg'],
        boStopLossValue: sl_val,
        boProfitValue: tp_val
      }

      result = Orders::Gateway.place_order(payload, source: self.class.name)
      return dry_run(payload, pos['tradingSymbol']) if result[:dry_run]

      handle_place_result(result, pos, sl_val, tp_val)
    end

    def handle_place_result(result, pos, sl_val, tp_val)
      if result[:order_id].present?
        notify("🛡️ Bracket order placed for #{pos['tradingSymbol']} (SL: #{sl_val}, TP: #{tp_val})")
        log_info("Bracket placed for #{pos['tradingSymbol']} #{result[:order_id]}")
      else
        log_error("Failed for #{pos['tradingSymbol']}: #{result[:message] || 'unknown error'}")
      end
    end

    def bracket_order_exists?(pos)
      Dhanhq::API::Orders.list.any? do |o|
        o['securityId'].to_s == pos['securityId'].to_s &&
          o['orderType'].to_s.upcase == 'BRACKET' &&
          %w[PENDING TRANSIT PART_TRADED].include?(o['orderStatus'])
      end
    end

    def detect_instrument_type(pos)
      if pos['exchangeSegment'].include?('FNO') || pos['productType'] == 'INTRADAY'
        :option
      else
        :stock
      end
    end

    def dry_run(payload, symbol)
      log_info("dry-run → #{payload.inspect}")

      notify(<<~MSG.strip, tag: 'DRYRUN')
        💡 DRY-RUN (PLACE_ORDER=false)
        • Symbol: #{symbol}
        • Qty: #{payload[:quantity]}
        • SL: ₹#{payload[:boStopLossValue]}
        • TP: ₹#{payload[:boProfitValue]}
      MSG
    end
  end
end
