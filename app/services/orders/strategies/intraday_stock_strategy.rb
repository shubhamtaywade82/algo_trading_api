module Orders
  module Strategies
    class IntradayStockStrategy < BaseStrategy
      def execute
        place_order(dhan_order_params)
      end

      private

      def leverage_factor
        mis_detail = instrument.mis_detail
        mis_detail&.mis_leverage.to_i || 1 # Default to 1x if no MIS details found
      end

      def calculate_quantity(price)
        available_funds = fetch_funds * 0.3 # Use 30% of funds
        max_quantity = (available_funds / price).floor
        lot_size = instrument.lot_size || 1

        # Adjust quantity based on lot size
        quantity = (max_quantity / lot_size) * lot_size
        [ quantity, lot_size ].max
      end

      def default_product_type
        Dhanhq::Constants::INTRA # Override default to intraday
      end
    end
  end
end
