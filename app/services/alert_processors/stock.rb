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
        quantity: calculate_quantity(ltp)
      }
    end

    # Handle intraday strategy
    def process_intraday_strategy
      order_params = build_order_payload(Dhanhq::Constants::INTRA)
      place_order(order_params)
    end

    # Handle swing strategy
    def process_swing_strategy
      order_params = build_order_payload(Dhanhq::Constants::MARGIN)
      place_order(order_params)
    end

    # Handle long-term strategy
    def process_long_term_strategy
      order_params = build_order_payload(Dhanhq::Constants::MARGIN)
      place_order(order_params)
    end

    # Place order using Dhan API
    def place_order(order_params)
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
      response['insufficientBalance']

      # raise "Insufficient margin: Missing ₹#{insufficient_balance}" if insufficient_balance.positive?

      response
    rescue StandardError => e
      raise "Margin validation failed: #{e.message}"
    end

    # Calculate the maximum quantity to trade
    def calculate_quantity(price)
      raw_available_balance = fetch_available_balance
      effective_funds = raw_available_balance * funds_utilization

      leveraged_price = price / leverage_factor

      max_quantity = (effective_funds / leveraged_price).floor
      required_funds = max_quantity * leveraged_price

      if raw_available_balance < required_funds
        raise "Insufficient funds: Required ₹#{required_funds}, Available ₹#{raw_available_balance} (Leverage: x#{leverage_factor})"
      end

      [max_quantity, 1].max # Ensure at least one unit
    end

    # Define leverage factor based on strategy type
    def leverage_factor
      return instrument.mis_detail&.mis_leverage.to_i || 1 if alert[:strategy_type] == 'intraday'

      1.0 # Default leverage for swing and long-term is 1x
    end

    # Funds utilization percentage
    def funds_utilization
      alert[:strategy_type] == 'intraday' ? 0.3 : 0.5
    end

    # Fetch available balance
    def fetch_available_balance
      Dhanhq::API::Funds.balance['availabelBalance'].to_f
    rescue StandardError
      raise 'Failed to fetch available balance'
    end
  end
end
