module Orders
  module Strategies
    class IntradayStockStrategy < BaseStrategy
      def execute
        place_order(dhan_order_params)
      end

      private

      def leverage_factor
        5.0 # Intraday trading leverage is 5x
      end

      def default_product_type
        Dhanhq::Constants::INTRA # Override default to intraday
      end
    end
  end
end
