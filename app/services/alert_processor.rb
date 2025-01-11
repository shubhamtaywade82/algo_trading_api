class AlertProcessor < ApplicationService
  def initialize(alert)
    @alert = alert
  end

  def call
    handle_open_position

    strategy = select_strategy
    raise "Strategy not found for instrument type: #{@alert[:instrument_type]}" unless strategy

    strategy.execute

    # setup_trailing_stop_loss(order_response) if order_response&.dig("orderId")

    @alert.update(status: "processed")
  rescue StandardError => e
    @alert.update(status: "failed", error_message: e.message)
    Rails.logger.error("Failed to process alert #{@alert.id}: #{e}")
  end

  private

  attr_reader :alert

  # Handle open positions and close them if profitable
  def handle_open_position
    position = fetch_open_position

    return unless position && position_profitable?(position)

    if opposite_signal?(position)
      if position_profitable?(position)
        close_position(position)
      elsif risk_reward_hit?(position)
        close_position(position)
      end
    end
  end

  def fetch_open_position
    positions = Dhanhq::API::Portfolio.positions
    positions.find { |pos| pos["tradingSymbol"] == alert[:ticker] && pos["positionType"] != "CLOSED" }
  end


  def position_profitable?(position)
    position["unrealizedProfit"].to_f > 20.00
  end

  def risk_reward_hit?(position)
    entry_price = position["entryPrice"].to_f
    target_price = entry_price + (entry_price - position["stopLoss"].to_f) * 2
    current_price = position["lastTradedPrice"].to_f
    current_price >= target_price
  end

  def opposite_signal?(position)
    alert[:action].upcase != position["positionType"]
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
    strategy_suffix = alert[:strategy_id]&.split("_")&.last

    case alert[:instrument_type].downcase
    when "stock"
      case strategy_suffix
      when "intraday" then Orders::Strategies::IntradayStockStrategy.new(alert)
      when "swing"    then Orders::Strategies::SwingStockStrategy.new(alert)
      when "long_term" then Orders::Strategies::StockOrderStrategy.new(alert)
      else
        raise "Unsupported stock strategy: #{strategy_suffix}"
      end
    when "index"
      case strategy_suffix
      when "intraday" then Orders::Strategies::IntradayIndexStrategy.new(alert)
      when "swing"    then Orders::Strategies::SwingIndexStrategy.new(alert)
      else
        raise "Unsupported index strategy: #{strategy_suffix}"
      end
    else
      raise "Unsupported instrument type: #{alert[:instrument_type]}"
    end
  end
end
