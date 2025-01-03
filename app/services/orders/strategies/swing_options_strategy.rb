module Orders
  module Strategies
    class SwingOptionsStrategy < IntradayOptionsStrategy
      private

      def default_product_type
        Dhanhq::Constants::CNC # Delivery-based options
      end
    end
  end
end
