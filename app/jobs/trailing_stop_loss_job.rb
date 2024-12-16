class TrailingStopLossJob < ApplicationJob
  queue_as :default

  def perform
    Position.where(status: "active").find_each do |position|
      latest_price = fetch_latest_price(position.ticker)
      new_stop_loss = calculate_new_stop_loss(position, latest_price)

      update_stop_loss_order(position, new_stop_loss) if new_stop_loss != position.stop_loss_price
    end
  end

  private

  def fetch_latest_price(ticker)
    # Fetch from WebSocket or other market feed
  end

  def calculate_new_stop_loss(position, latest_price)
    return position.stop_loss_price if latest_price <= position.entry_price

    delta = position.trailing_stop_loss
    position.action == "BUY" ? latest_price - delta : latest_price + delta
  end

  def update_stop_loss_order(position, new_stop_loss)
    Dhanhq::API::Orders.modify(position.dhan_order_id, triggerPrice: new_stop_loss)
    position.update(stop_loss_price: new_stop_loss)
  end
end
