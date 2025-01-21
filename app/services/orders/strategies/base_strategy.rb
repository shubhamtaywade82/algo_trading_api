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

      # Validate margin before placing an order
      def validate_margin(params)
        params = params.merge(price: instrument.ltp)
        response = Dhanhq::API::Funds.margin_calculator(params)
        insufficient_balance = response['insufficientBalance'].to_f

        raise "Insufficient margin: Missing ₹#{insufficient_balance}" if insufficient_balance.positive?

        response
      rescue StandardError => e
        raise "Margin validation failed: #{e.message}"
      end

      # Prepare common order parameters for stock
      def build_order_payload
        {
          transactionType: alert[:action].upcase,
          orderType: alert[:order_type].upcase,
          productType: determine_product_type,
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
        available_funds = fetch_funds * funds_utilization * leverage_factor
        max_quantity = (available_funds / price).floor
        [max_quantity, 1].max
      end

      def determine_product_type
        case alert[:strategy_type]
        when 'intraday'
          Dhanhq::Constants::INTRA
        else
          Dhanhq::Constants::MARGIN
        end
      end

      def leverage_factor
        1.0 # Default leverage is 1x
      end

      def funds_utilization
        0.3 # 30% utilization of funds
      end

      # Default product type (can be overridden by subclasses)
      def default_product_type
        Dhanhq::Constants::MARGIN # Default to intraday
      end

      # Place an order using Dhan API
      def place_order(params)
        Rails.logger.debug params
        # validate_margin(params)
        if ENV['PLACE_ORDER'] == 'true'
          executed_order = Dhanhq::API::Orders.place(params)

          dhan_order = OrdersService.fetch_order(executed_order[:orderId])
          order = Order.new(
            dhan_order_id: dhan_order[:orderId],
            transaction_type: dhan_order[:transactionType],
            product_type: dhan_order[:productType],
            order_type: dhan_order[:orderType],
            validity: dhan_order[:validity],
            exchange_segment: dhan_order[:exchangeSegment],
            security_id: dhan_order[:securityId],
            quantity: dhan_order[:quantity],
            disclosed_quantity: dhan_order[:disclosedQuantity],
            price: dhan_order[:price],
            trigger_price: dhan_order[:triggerPrice],
            bo_profit_value: dhan_order[:boProfitValue],
            bo_stop_loss_value: dhan_order[:boStopLossValue],
            ltp: dhan_order[:price],
            order_status: dhan_order[:orderStatus],
            filled_qty: dhan_order[:filled_qty],
            average_traded_price: (dhan_order[:price] * dhan_order[:quantity]),
            alert_id: alert[:id]
          )
          order.save
        else
          Rails.logger.info("PLACE_ORDER is disabled. Order parameters: #{params}")
        end
      rescue StandardError => e
        raise "Failed to place order: #{e.message}"
      end
    end
  end
end
