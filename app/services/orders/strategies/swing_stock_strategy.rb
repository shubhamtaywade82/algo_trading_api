# frozen_string_literal: true

module Orders
  module Strategies
    class SwingStockStrategy < BaseStrategy
      def execute
        place_order(build_order_payload.merge(productType: Dhanhq::Constants::CNC))
      end

      private

      def default_product_type
        Dhanhq::Constants::CNC # Delivery-based product
      end
    end
  end
end
