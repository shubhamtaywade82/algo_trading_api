# frozen_string_literal: true

# Places a bracket (SL+TP) order for every new open position not having one.
module Orders
  class BracketPlacer < ApplicationService
    # Scans all active positions and places missing brackets
    # @return [void]
    def self.call
      Positions::ActiveCache.ids.each do |sec_id|
        pos = Positions::ActiveCache.fetch(sec_id)
        next unless pos
        next if bracket_order_exists?(pos)

        # Calculate SL/TP for new bracket order (customize rules as needed)
        sl_val = (pos['buyAvg'].to_f * 0.8).round(2)   # 20% SL
        tp_val = (pos['buyAvg'].to_f * 1.5).round(2)   # 50% TP

        payload = {
          securityId: pos['securityId'],
          transactionType: pos['netQty'].to_f.positive? ? 'SELL' : 'BUY',
          orderType: 'BRACKET',
          quantity: pos['netQty'].abs,
          exchangeSegment: pos['exchangeSegment'],
          productType: pos['productType'],
          validity: 'DAY',
          price: pos['ltp'] || pos['buyAvg'],
          boStopLossValue: sl_val,
          boProfitValue: tp_val
        }
        response = Dhanhq::API::Orders.place(payload)
        if response['orderId']
          TelegramNotifier.send_message("🛡️ Bracket order placed for #{pos['tradingSymbol']} (SL: #{sl_val}, TP: #{tp_val})")
          Rails.logger.info("[BracketPlacer] Bracket placed for #{pos['tradingSymbol']} #{response['orderId']}")
        else
          Rails.logger.error("[BracketPlacer] Failed for #{pos['tradingSymbol']}: #{response['message']}")
        end
      end
    end

    # Checks if an open bracket order exists for the position
    # @param [Hash] pos
    # @return [Boolean]
    def self.bracket_order_exists?(pos)
      Dhanhq::API::Orders.list.any? do |o|
        o['securityId'].to_s == pos['securityId'].to_s &&
          o['orderType'].to_s.upcase == 'BRACKET' &&
          %w[PENDING TRANSIT PART_TRADED].include?(o['orderStatus'])
      end
    end
  end
end
