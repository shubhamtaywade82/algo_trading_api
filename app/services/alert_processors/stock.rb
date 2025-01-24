# frozen_string_literal: true

module AlertProcessors
  class Stock < Base
    def call
      Rails.logger.info("Processing stock alert: #{alert.inspect}")

      case alert[:strategy_type]
      when 'intraday'
        process_intraday_strategy
      when 'swing'
        process_swing_strategy
      when 'long_term'
        process_long_term_strategy
      else
        raise "Unsupported strategy type: #{alert[:strategy_type]}"
      end

      alert.update!(status: 'processed')
    rescue StandardError => e
      alert.update!(status: 'failed', error_message: e.message)
      Rails.logger.error("Failed to process stock alert: #{e.message}")
    end

    private

    # Common logic to prepare order payload
    def build_order_payload(product_type)
      {
        transactionType: alert[:action].upcase,
        orderType: alert[:order_type].upcase,
        productType: product_type,
        validity: Dhanhq::Constants::DAY,
        securityId: instrument.security_id,
        exchangeSegment: instrument.exchange_segment,
        quantity: calculate_quantity(instrument.ltp)
      }
    end

    # Handle intraday strategy
    def process_intraday_strategy
      order_params = build_order_payload(Dhanhq::Constants::INTRA)
      place_order(order_params)
    end

    # Handle swing strategy
    def process_swing_strategy
      order_params = build_order_payload(Dhanhq::Constants::CNC)
      place_order(order_params)
    end

    # Handle long-term strategy
    def process_long_term_strategy
      order_params = build_order_payload(Dhanhq::Constants::CNC)
      place_order(order_params)
    end

    # Place order using Dhan API
    def place_order(order_params)
      validate_margin(order_params)

      if ENV['PLACE_ORDER'] == 'true'
        executed_order = Dhanhq::API::Orders.place(order_params)
        Rails.logger.info("Order placed successfully: #{executed_order}")
      else
        Rails.logger.info("PLACE_ORDER is disabled. Order parameters: #{order_params}")
      end
    rescue StandardError => e
      raise "Failed to place order: #{e.message}"
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

    # Calculate the maximum quantity to trade
    def calculate_quantity(price)
      available_funds = fetch_funds * funds_utilization * leverage_factor
      max_quantity = (available_funds / price).floor
      [max_quantity, 1].max # Ensure at least one unit
    end

    # Fetch available funds
    def fetch_funds
      Dhanhq::API::Funds.balance['availabelBalance'].to_f
    rescue StandardError => e
      raise "Failed to fetch funds: #{e.message}"
    end

    # Define leverage factor based on strategy type
    def leverage_factor
      return instrument.mis_detail&.mis_leverage.to_i || 1 if alert[:strategy_type] == 'intraday'

      1.0 # Default leverage for swing and long-term is 1x
    end

    # Funds utilization percentage
    def funds_utilization
      case alert[:strategy_type]
      when 'intraday'
        0.3 # 30% of available funds for intraday
      else
        0.5 # 50% of available funds for swing or long-term
      end
    end
  end
end
