class TrailingStopLossJob < ApplicationJob
  queue_as :default

  def perform
    positions = Dhanhq::API::Portfolio.positions

    positions.each do |position|
      next if position["positionType"] == "CLOSED"

      new_stop_loss = calculate_new_stop_loss(position)

      update_stop_loss_order(position, new_stop_loss) if new_stop_loss != position["stopLoss"]
    end
  rescue StandardError => e
    Rails.logger.error("TrailingStopLossJob failed: #{e.message}")
  end

  private

  def fetch_latest_price(ticker)
    # Fetch from WebSocket or other market feed
  end

  def calculate_new_stop_loss(position)
    entry_price = position["entryPrice"].to_f
    current_price = position["lastTradedPrice"].to_f
    trailing_amount = position["trailingStopLoss"].to_f

    return position["stopLoss"] if current_price <= entry_price

    position["positionType"] == "LONG" ? current_price - trailing_amount : current_price + trailing_amount
  end

  def update_stop_loss_order(position, new_stop_loss)
    Dhanhq::API::Orders.modify(position["orderId"], triggerPrice: new_stop_loss)
  rescue StandardError => e
    Rails.logger.error("Failed to update stop-loss for position #{position['tradingSymbol']}: #{e.message}")
  end
end
