module Orders
  module Strategies
    class BaseStrategy
      attr_reader :alert

      def initialize(alert)
        @alert = alert
      end

      def execute
        raise NotImplementedError, "#{self.class} must implement #execute"
      end

      private

      def dhan_order_params
        {
          transactionType: alert[:action].upcase,
          orderType: "MARKET",
          productType: Dhanhq::Constants::INTRA, # Intraday by default
          validity: "DAY"
        }
      end

      def fetch_security_id(symbol, exchange: nil, instrument_type: nil)
        query = { underlying_symbol: symbol }
        query[:exch_id] = exchange if exchange
        # query[:instrument_type] = instrument_type if instrument_type
        Instrument.find_by(query)&.security_id
      end

      def calculate_quantity(price, lot_size: 1, utilization: 0.3)
        available_funds = fetch_funds * utilization
        (available_funds / (price * lot_size)).floor
      end

      def fetch_funds
        Dhanhq::API::Funds.balance["availabelBalance"].to_f
      end

      def place_order(params)
        Dhanhq::API::Orders.place(params)
      rescue StandardError => e
        raise "Failed to place order: #{e.message}"
      end
    end
  end
end
