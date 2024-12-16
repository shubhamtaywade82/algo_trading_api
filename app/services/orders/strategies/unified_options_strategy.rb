module Orders
  module Strategies
    class UnifiedOptionsStrategy < BaseStrategy
      def execute
        place_order(
          dhan_order_params.merge(
            strikePrice: calculate_strike_price(alert[:current_price]),
            quantity: calculate_quantity(alert[:current_price])
          )
        )
      end

      private

      def calculate_strike_price(price)
        step = instrument.tick_size || 50
        (price / step).round * step
      end
    end
  end
end
