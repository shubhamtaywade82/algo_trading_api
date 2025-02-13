# frozen_string_literal: true

module AlertProcessors
  # Stock processes TradingView alerts for equity (stock) instruments.
  # It handles different strategy types (intraday, swing, long_term),
  # builds appropriate order parameters, and places orders if allowed by
  # environment configuration (PLACE_ORDER). If any step fails, it updates
  # the alert status to "failed" and logs the error.
  class Stock < Base
    # The main entry point for processing a stock alert.
    # Based on `alert[:strategy_type]`, it calls the relevant private method:
    #  - `process_intraday_strategy`
    #  - `process_swing_strategy`
    #  - `process_long_term_strategy`
    #
    # If it fails at any step, the alert status is updated to "failed",
    # with the error message logged. Otherwise, the alert status is set to "processed".
    #
    # @return [void]
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

    # Processes an intraday strategy by building an INTRA order payload
    # and placing the order.
    #
    # @return [void]
    #
    def process_intraday_strategy
      order_params = build_order_payload(Dhanhq::Constants::INTRA)
      place_order(order_params)
    end

    # Processes a swing strategy by building a MARGIN order payload
    # and placing the order.
    #
    # @return [void]
    def process_swing_strategy
      order_params = build_order_payload(Dhanhq::Constants::MARGIN)
      place_order(order_params)
    end

    # Processes a long-term strategy by building a MARGIN order payload
    # and placing the order.
    #
    # @return [void]
    def process_long_term_strategy
      order_params = build_order_payload(Dhanhq::Constants::MARGIN)
      place_order(order_params)
    end

    # Builds a hash of order parameters common to all strategies, with a
    # specified product type (e.g., INTRA or MARGIN).
    #
    # @param product_type [String] The product type constant (e.g. `Dhanhq::Constants::INTRA`).
    # @return [Hash] The payload required by the Dhanhq::API::Orders.place method.
    def build_order_payload(product_type)
      {
        transactionType: alert[:action].upcase,
        orderType: alert[:order_type].upcase,
        productType: product_type,
        validity: Dhanhq::Constants::DAY,
        securityId: instrument.security_id,
        exchangeSegment: instrument.exchange_segment,
        quantity: validate_quantity(calculate_quantity(ltp))
      }
    end

    # Places the order using Dhan API if PLACE_ORDER is set to 'true';
    # otherwise logs order parameters without placing an order.
    #
    # @param order_params [Hash] The order payload to be sent to Dhanhq::API::Orders.place
    # @return [void]
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

    # Validates margin before placing an order (unused in the current example).
    # Demonstrates how you might extend functionality, e.g., by calling
    # Dhanhq::API::Funds.margin_calculator.
    #
    # @param params [Hash] A hash of order details used to calculate margin.
    # @return [Hash] The API response indicating margin details, if successful.
    def validate_margin(params)
      params = params.merge(price: instrument.ltp)
      response = Dhanhq::API::Funds.margin_calculator(params)
      response['insufficientBalance']

      # raise "Insufficient margin: Missing ₹#{insufficient_balance}" if insufficient_balance.positive?

      response
    rescue StandardError => e
      raise "Margin validation failed: #{e.message}"
    end

    # Calculates the maximum quantity to trade, ensuring it doesn't exceed
    # available balance and applies any leverage or lot constraints.
    #
    # @param price [Float] The current LTP (Last Traded Price) of the instrument.
    # @return [Integer] The final computed quantity to trade.
    def calculate_quantity(price)
      raw_available_balance = fetch_available_balance
      effective_funds = raw_available_balance * funds_utilization

      leveraged_price = price / leverage_factor

      max_quantity = (effective_funds / leveraged_price).floor
      required_funds = max_quantity * leveraged_price

      if raw_available_balance < required_funds
        raise "Insufficient funds: Required ₹#{required_funds}, " \
              "Available ₹#{raw_available_balance} (Leverage: x#{leverage_factor})"
      end

      max_quantity
    end

    def validate_quantity(quantity)
      if quantity <= 1
        raise "Trade quantity is too small (#{quantity}). Minimum trade size should be greater than 1 to avoid high trading costs."
      end

      quantity
    end

    # Defines the leverage factor based on the alert’s strategy type.
    # If it's intraday, it returns the MIS leverage (or 1 if undefined).
    # Otherwise, returns 1x leverage for swing/long_term.
    #
    # @return [Float] The numeric leverage multiplier.
    def leverage_factor
      return instrument.mis_detail&.mis_leverage.to_i || 1 if alert[:strategy_type] == 'intraday'

      1.0 # Default leverage for swing and long-term is 1x
    end

    # Defines what fraction of total funds is utilized.
    # For intraday, we use 30% (0.3); for swing or long_term, 50% (0.5).
    #
    # @return [Float] A decimal representing fraction of total funds to use.
    def funds_utilization
      alert[:strategy_type] == 'intraday' ? 0.3 : 0.5
    end

    # Fetches available balance from Dhanhq::API::Funds.
    # Raises an error if the API call fails.
    #
    # @return [Float] The current available balance in the trading account.
    def fetch_available_balance
      Dhanhq::API::Funds.balance['availabelBalance'].to_f
    rescue StandardError
      raise 'Failed to fetch available balance'
    end
  end
end
