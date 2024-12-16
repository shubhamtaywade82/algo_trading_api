module Orders
  module Strategies
    class CryptoOrderStrategy < BaseStrategy
      def execute
        place_order(dhan_order_params)
      end

      private

      def exchange
        "CRYPTO" # Override the default exchange in BaseStrategy
      end
    end
  end
end
