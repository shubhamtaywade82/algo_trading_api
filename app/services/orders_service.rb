# frozen_string_literal: true

class OrdersService
  def self.fetch_orders
    retries ||= 0
    Dhanhq::API::Orders.list
  rescue StandardError => e
    ErrorHandler.handle_error(
      context: 'Fetching orders',
      exception: e,
      retries: retries + 1,
      retry_logic: -> { fetch_orders }
    )
  end

  def self.fetch_order(order_id)
    retries ||= 0
    Dhanhq::API::Orders.find(order_id)
  rescue StandardError => e
    ErrorHandler.handle_error(
      context: 'Fetching orders',
      exception: e,
      retries: retries + 1,
      retry_logic: -> { fetch_orders }
    )
  end

  # Place a generic order
  # @param payload [Hash] The payload for the order, including keys like :transactionType, :exchangeSegment, etc.
  # @return [Hash] The response from the DhanHQ API
  def self.place_order(payload)
    response = Dhanhq::API::Orders.place(payload)
    handle_response(response)
  end

  # Place a slicing order
  # @param payload [Hash] The payload for the slicing order, including keys like :quantity, :disclosedQuantity, etc.
  # @return [Hash] The response from the DhanHQ API
  def self.place_sliced_order(payload)
    response = Dhanhq::API::Orders.slice(payload)
    handle_response(response)
  end

  # Handle API response
  # @param response [Hash] The response from the DhanHQ API
  # @return [Hash] The processed response
  def self.handle_response(response)
    if response['status'] == 'success'
      Rails.logger.info("Order placed successfully: #{response['orderId']}")
      response
    else
      Rails.logger.error("Order placement failed: #{response['error']}")
      { error: response['error'] }
    end
  rescue StandardError => e
    Rails.logger.error("Error placing order: #{e.message}")
    { error: 'Unexpected error occurred. Please try again later.' }
  end

  # Place a generic order
  # @param payload [Hash] The payload for the order
  # @return [Hash] The response from the DhanHQ API
  def self.place(payload)
    place_order(payload)
  end

  # Place a limit order
  # @param correlation_id [String] A unique ID for correlation
  # @param transaction_type [String] "BUY" or "SELL"
  # @param exchange_segment [String] The segment of the exchange
  # @param product_type [String] The product type like "CNC", "INTRADAY"
  # @param security_id [String] The ID of the security
  # @param quantity [Integer] Number of shares
  # @param price [Float] The limit price
  # @return [Hash] The response from the DhanHQ API
  def self.place_limit_order(**args)
    place_order(order_payload(args, 'LIMIT'))
  end

  # Place a market order
  # @param args [Hash] Additional parameters for the order, similar to place_limit_order
  # @return [Hash] The response from the DhanHQ API
  def self.place_market_order(**args)
    place_order(order_payload(args, 'MARKET'))
  end

  # Place a stop-loss limit order
  # @param trigger_price [Float] The trigger price for the order
  # @param args [Hash] Additional parameters for the order
  # @return [Hash] The response from the DhanHQ API
  def self.place_stop_loss_limit_order(trigger_price:, **args)
    place_order(order_payload(args, 'STOP_LOSS', trigger_price: trigger_price))
  end

  # Place a bracket order
  # @param bo_profit_value [Float] Target price for the bracket order
  # @param bo_stop_loss_value [Float] Stop-loss price for the bracket order
  # @param args [Hash] Additional parameters for the order
  # @return [Hash] The response from the DhanHQ API
  def self.place_bracket_order(bo_profit_value:, bo_stop_loss_value:, **args)
    place_order(order_payload(args, 'LIMIT', product_type: 'BO', boProfitValue: bo_profit_value,
                                             boStopLossValue: bo_stop_loss_value))
  end

  # Place a slicing order
  # @param disclosed_quantity [Integer] Quantity to disclose in the market depth
  # @param args [Hash] Additional parameters for the order
  # @return [Hash] The response from the DhanHQ API
  def self.place_slicing_order(disclosed_quantity:, **args)
    place_sliced_order(order_payload(args, 'MARKET', disclosedQuantity: disclosed_quantity))
  end

  # Build the payload for an order
  # @param args [Hash] The base arguments for the order
  # @option args [String] :correlation_id A unique ID for correlation
  # @option args [String] :transaction_type "BUY" or "SELL"
  # @option args [String] :exchange_segment The segment of the exchange
  # @option args [String] :product_type The product type like "CNC", "INTRADAY"
  # @option args [String] :security_id The ID of the security
  # @option args [Integer] :quantity Number of shares
  # @option args [Float] :price The order price
  # @param order_type [String] The type of the order
  # @param additional [Hash] Additional arguments for the order
  # @return [Hash] The payload for the order
  def self.order_payload(args, order_type, additional = {})
    {
      correlationId: args[:correlation_id],
      transactionType: args[:transaction_type],
      exchangeSegment: args[:exchange_segment],
      productType: args[:product_type] || 'INTRADAY',
      orderType: order_type,
      validity: 'DAY',
      securityId: args[:security_id],
      quantity: args[:quantity],
      price: args[:price]
    }.merge(additional.compact)
  end
end
