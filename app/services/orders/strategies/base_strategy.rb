module Orders
  module Strategies
    class BaseStrategy
      attr_reader :alert, :instrument, :security_symbol, :exchange

      def initialize(alert)
        @alert = alert
        @security_symbol = alert[:ticker]
        @exchange = alert[:market] || "NSE"
      end

      def execute
        raise NotImplementedError, "#{self.class} must implement #execute"
      end

      private

      # Fetch the instrument record
      def instrument
        @instrument ||= Instrument.find_by!(
          exch_id: exchange,
          underlying_symbol: security_symbol
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
          exchangeSegment: map_exchange_segment(instrument.exch_id),
          quantity: calculate_quantity(alert[:current_price])
        }
      end

      # Map exchange segments dynamically
      def map_exchange_segment(exchange)
        Dhanhq::Constants::EXCHANGE_SEGMENTS.find { |seg| seg.include?(exchange) } ||
          raise("Unsupported exchange: #{exchange}")
      end

      def calculate_quantity(price)
        available_funds = fetch_funds * leverage_factor
        lot_size = instrument.lot_size || 1
        max_quantity = (available_funds / price).floor

        # Adjust quantity to be a multiple of lot size
        quantity = (max_quantity / lot_size) * lot_size
        [ quantity, lot_size ].max
      end

      def leverage_factor
        1.0 # Default leverage is 1x
      end

      # Default product type (can be overridden by subclasses)
      def default_product_type
        Dhanhq::Constants::INTRA # Default to intraday
      end

      # Place an order using Dhan API
      def place_order(params)
        Dhanhq::API::Orders.place(params)
      rescue StandardError => e
        raise "Failed to place order: #{e.message}"
      end
    end
  end
end
