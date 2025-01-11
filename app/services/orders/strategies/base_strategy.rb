# frozen_string_literal: true

module Orders
  module Strategies
    class BaseStrategy
      attr_reader :alert, :security_symbol, :exchange

      def initialize(alert)
        @alert = alert
        @security_symbol = alert[:ticker]
        @exchange = alert[:exchange]
      end

      def execute
        raise NotImplementedError, "#{self.class} must implement #execute"
      end

      private

      # Fetch the instrument record for stock type
      def instrument
        @instrument ||= Instrument.find_by!(
          exchange: exchange,
          underlying_symbol: security_symbol,
          segment: 'equity' # Only process stocks
        )
      rescue ActiveRecord::RecordNotFound
        raise "Instrument not found for #{security_symbol} in #{exchange}"
      end

      # Fetch available funds
      def fetch_funds
        Dhanhq::API::Funds.balance['availabelBalance'].to_f
      rescue StandardError => e
        raise "Failed to fetch funds: #{e.message}"
      end

      # Prepare common order parameters for stock
      def dhan_order_params
        {
          transactionType: alert[:action].upcase,
          orderType: alert[:order_type].upcase,
          productType: default_product_type,
          validity: Dhanhq::Constants::DAY,
          securityId: instrument.security_id,
          exchangeSegment: instrument.exchange_segment,
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
        max_quantity = (utilized_funds / price).floor
        [max_quantity, 1].max
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
        Rails.logger.debug params
        Dhanhq::API::Orders.place(params)
      rescue StandardError => e
        raise "Failed to place order: #{e.message}"
      end
    end
  end
end
