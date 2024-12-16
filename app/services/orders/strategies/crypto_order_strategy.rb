## this is not applicable for DHANHQ

module Orders
  module Strategies
    class CryptoOrderStrategy < BaseStrategy
      def execute
        security_id = fetch_security_id(alert[:ticker], exchange: "CRYPTO")
        raise "Security ID not found for #{alert[:ticker]}" unless security_id

        order_params = dhan_order_params.merge(
          exchangeSegment: "CRYPTO",
          securityId: security_id,
          quantity: calculate_quantity(alert[:current_price])
        )

        place_order(order_params)
      end
    end
  end
end
