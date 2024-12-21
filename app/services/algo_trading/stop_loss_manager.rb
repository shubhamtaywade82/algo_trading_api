# app/services/algo_trading/stop_loss_manager.rb
module AlgoTrading
  class StopLossManager
    def initialize
      @order_update_handler = WebsocketHandlers::OrderUpdateHandler.new
    end

    def adjust_stop_loss(order, market_data)
      new_stop_loss = calculate_stop_loss(market_data["last_price"])
      Dhanhq::API::Orders.modify(order_id: order[:id], stop_loss_price: new_stop_loss)
    end

    def calculate_stop_loss(current_price)
      (current_price * 0.98).round(2) # 2% below current price
    end
  end
end
