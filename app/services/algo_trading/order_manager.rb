# app/services/algo_trading/order_manager.rb
module AlgoTrading
  class OrderManager
    def initialize
      @market_feed_handler = WebsocketHandlers::MarketFeedHandler.new
      @order_update_handler = WebsocketHandlers::OrderUpdateHandler.new
    end

    def start
      Thread.new { @market_feed_handler.listen }
      Thread.new { @order_update_handler.listen }
    end

    def place_order(alert, market_data)
      order_params = {
        transactionType: alert[:action].upcase,
        orderType: "LIMIT",
        price: calculate_limit_price(market_data),
        securityId: alert[:security_id],
        quantity: calculate_quantity(alert[:current_price]),
        productType: "INTRA"
      }
      Dhanhq::API::Orders.place(order_params)
    end

    def calculate_limit_price(market_data)
      # Use precision of 0.05 for limit orders
      (market_data["last_price"] * 0.95).round(2)
    end

    def calculate_quantity(price)
      available_funds = Dhanhq::API::Funds.balance["availabelBalance"].to_f
      (available_funds * 0.3 / price).floor
    end
  end
end
