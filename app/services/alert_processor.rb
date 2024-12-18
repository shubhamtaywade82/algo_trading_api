class AlertProcessor < ApplicationService
  def initialize(alert)
    @alert = alert
  end

  def call
    handle_open_position

    strategy = select_strategy
    raise "Strategy not found for instrument type: #{@alert[:instrument_type]}" unless strategy

    order_response = strategy.execute

    setup_trailing_stop_loss(order_response) if order_response&.dig("orderId")

    @alert.update(status: "processed")
  rescue StandardError => e
    @alert.update(status: "failed", error_message: e.message)
    Rails.logger.error("Failed to process alert #{@alert.id}: #{e.message}")
  end

  private

  attr_reader :alert

  # Handle open positions and close them if profitable
  def handle_open_position
    position = fetch_open_position

    return unless position && position_profitable?(position)

    close_position(position)
  end

  def fetch_open_position
    positions = Dhanhq::API::Portfolio.positions
    positions.find { |pos| pos["tradingSymbol"] == alert[:ticker] && pos["positionType"] != "CLOSED" }
  end

  def position_profitable?(position)
    position["unrealizedProfit"].to_f > 20.00
  end

  def close_position(position)
    order_data = {
      transactionType: position["positionType"] == "LONG" ? "SELL" : "BUY",
      exchangeSegment: position["exchangeSegment"],
      productType: position["productType"],
      orderType: "MARKET",
      validity: "DAY",
      securityId: position["securityId"],
      quantity: position["netQty"]
    }

    Dhanhq::API::Orders.place(order_data)
  rescue StandardError => e
    raise "Failed to close position for #{position['tradingSymbol']}: #{e.message}"
  end

  def select_strategy
    case alert[:instrument_type].downcase
    when "stock"
      case alert[:strategy_type]
      when "intraday" then Orders::Strategies::IntradayStockStrategy.new(alert)
      when "swing"    then Orders::Strategies::SwingStockStrategy.new(alert)
      when "long_term" then Orders::Strategies::StockOrderStrategy.new(alert)
      end
    when "index", "option"
      Orders::Strategies::OptionsStrategy.new(alert)
    else
      nil
    end
  end

  def setup_trailing_stop_loss(order_response)
    order_details = fetch_order_details(order_response["orderId"])

    return unless order_details

    TrailingStopLossService.new(
      order_id: order_details["orderId"],
      security_id: order_details["securityId"],
      transaction_type: alert[:action],
      trailing_stop_loss_percentage: alert[:trailing_stop_loss]
    ).call
  end

  def fetch_order_details(order_id)
    response = Dhanhq::API::Orders.get_order_by_id(order_id)
    raise "Failed to fetch order details for order ID #{order_id}" unless response

    response
  end
end
