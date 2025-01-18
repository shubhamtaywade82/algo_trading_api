# frozen_string_literal: true

module Orders
  module Strategies
    class StockOrderStrategy < BaseStrategy
      def execute
        place_order(build_order_payload)
      end
    end
  end
end
