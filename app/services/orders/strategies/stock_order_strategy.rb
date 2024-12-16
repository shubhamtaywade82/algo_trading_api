module Orders
  module Strategies
    class StockOrderStrategy < BaseStrategy
      def execute
        security_id = fetch_security_id(alert[:ticker], exchange: "NSE", instrument_type: "EQUITY")
        raise "Security ID not found for #{alert[:ticker]}" unless security_id

        order_params = dhan_order_params.merge(
          exchangeSegment: "NSE_EQ",
          securityId: security_id,
          quantity: calculate_quantity(alert[:current_price])
        )

        place_order(order_params)
      end
    end
  end
end
