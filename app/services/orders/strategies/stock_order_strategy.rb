module Orders
  module Strategies
    class StockOrderStrategy < BaseStrategy
      def execute
        place_order(dhan_order_params)
      end
    end
  end
end
