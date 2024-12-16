module Orders
  module Strategies
    class SwingStockStrategy < BaseStrategy
      def execute
        place_order(dhan_order_params.merge(productType: Dhanhq::Constants::CNC))
      end

      private

      def default_product_type
        Dhanhq::Constants::CNC # Delivery-based product
      end
    end
  end
end
