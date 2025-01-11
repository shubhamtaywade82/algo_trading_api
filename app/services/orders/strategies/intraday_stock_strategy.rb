# frozen_string_literal: true

module Orders
  module Strategies
    class IntradayStockStrategy < BaseStrategy
      def execute
        place_order(dhan_order_params.merge(productType: Dhanhq::Constants::INTRA))
      end

      private

      def leverage_factor
        mis_detail = instrument.mis_detail
        mis_detail&.mis_leverage.to_i || 1 # Use MIS leverage if available, default to 1x
      end

      def calculate_quantity(price)
        available_funds = fetch_funds * 0.3 # Use 30% of available funds
        max_quantity = (available_funds / price).floor
        [max_quantity, 1].max # Ensure at least 1 quantity
      end
    end
  end
end
