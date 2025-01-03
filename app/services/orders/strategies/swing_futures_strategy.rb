module Orders
  module Strategies
    class SwingFuturesStrategy < IntradayFuturesStrategy
      private

      def default_product_type
        Dhanhq::Constants::CNC # Swing Trading Futures
      end
    end
  end
end
