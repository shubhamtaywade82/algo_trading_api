module Orders
  module Strategies
    class UnifiedOptionsStrategy < BaseStrategy
      def execute
        security_id = fetch_security_id(alert[:ticker], exchange: "NSE_FNO")
        raise "Security ID not found for #{alert[:ticker]}" unless security_id

        strike_price = calculate_strike_price(alert[:current_price])
        lot_size = Instrument.find_by(symbol_name: alert[:ticker])&.lot_size || 1
        quantity = calculate_quantity(strike_price, lot_size: lot_size)

        order_params = dhan_order_params.merge(
          exchangeSegment: "NSE_FNO",
          securityId: security_id,
          quantity: quantity
        )

        place_order(order_params)
      end

      private

      def calculate_strike_price(price)
        step = 50 # Typical step for NIFTY options
        (price / step).round * step
      end
    end
  end
end
