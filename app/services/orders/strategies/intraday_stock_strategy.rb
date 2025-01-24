# frozen_string_literal: true

module Orders
  module Strategies
    class IntradayStockStrategy < BaseStrategy
      def execute
        order_params = build_order_payload.merge(productType: Dhanhq::Constants::INTRA)

        place_order(order_params)
      end

      private

      def leverage_factor
        mis_detail = instrument.mis_detail
        mis_detail&.mis_leverage.to_i || 1 # Use MIS leverage if available, default to 1x
      end
    end
  end
end
