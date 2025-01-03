module Orders
  module Strategies
    class IntradayFuturesStrategy < BaseStrategy
      def execute
        place_order(dhan_order_params.merge(productType: Dhanhq::Constants::INTRA))
      end
    end
  end
end
