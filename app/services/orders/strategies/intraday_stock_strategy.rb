# frozen_string_literal: true

module Orders
  module Strategies
    class IntradayStockStrategy < BaseStrategy
      def execute
        place_order(build_order_payload.merge(productType: Dhanhq::Constants::INTRA))
      end

      private

      def leverage_factor
        mis_detail = instrument.mis_detail
        mis_detail&.mis_leverage.to_i || 1 # Use MIS leverage if available, default to 1x
      end
    end
  end
end
