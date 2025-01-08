module Orders
  module Strategies
    class BaseStrategy
      attr_reader :alert, :instrument, :security_symbol, :exchange

      def initialize(alert)
        @alert = alert
        @security_symbol = alert[:ticker]
        @exchange = alert[:exchange]
      end

      def execute
        raise NotImplementedError, "#{self.class} must implement #execute"
      end

      private

      # Fetch the instrument record
      def instrument
        @instrument ||= Instrument.find_by!(
          exchange: exchange,
          underlying_symbol: security_symbol,
          instrument_type: alert[:instrument_type] == "stock" ? "ES" : "INDEX"
        )
      rescue ActiveRecord::RecordNotFound
        raise "Instrument not found for #{security_symbol} in #{exchange}"
      end

      # Fetch available funds
      def fetch_funds
        Dhanhq::API::Funds.balance["availabelBalance"].to_f
      end

      # Prepare common order parameters
      def dhan_order_params
        {
          transactionType: alert[:action].upcase,
          orderType: Dhanhq::Constants::MARKET,
          productType: default_product_type,
          validity: Dhanhq::Constants::DAY,
          securityId: instrument.security_id,
          exchangeSegment: map_exchange_segment(instrument.exchange_segment),
          quantity: calculate_quantity(alert[:current_price])
        }
      end

      # Map exchange segments dynamically
      def map_exchange_segment(exchange)
        Dhanhq::Constants::EXCHANGE_SEGMENTS.find { |seg| seg.include?(exchange) } ||
          raise("Unsupported exchange: #{exchange}")
      end

      def calculate_quantity(price)
        utilized_funds = fetch_funds * funds_utilization * leverage_factor

        lot_size = instrument.lot_size || 1
        max_quantity = (utilized_funds / price).floor

        quantity = (max_quantity / lot_size) * lot_size
        [ quantity, lot_size ].max
      end

      def leverage_factor
        1.0 # Default leverage is 1x
      end

      def funds_utilization
        0.3 # 30% utilization of funds
      end

      # Default product type (can be overridden by subclasses)
      def default_product_type
        Dhanhq::Constants::INTRA # Default to intraday
      end

      # Place an order using Dhan API
      def place_order(params)
        pp params
        Dhanhq::API::Orders.place(params)
      rescue StandardError => e
        raise "Failed to place order: #{e.message}"
      end
    end
  end
end
