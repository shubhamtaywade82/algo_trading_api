# app/services/order_service.rb
class OrderService
  def self.place_order(ticker:, action:, quantity:, price:, security_id:, trailing_stop_loss:)
    response = Dhanhq::API::Orders.place(
      transactionType: action.upcase,
      exchangeSegment: "NSE_EQ",
      productType: "CNC",
      orderType: "MARKET",
      securityId: security_id,
      quantity: quantity,
      price: price
    )

    Order.create(
      ticker: ticker,
      action: action,
      quantity: quantity,
      price: price,
      dhan_order_id: response["orderId"],
      dhan_status: response["orderStatus"],
      security_id: security_id,
      stop_loss_price: calculate_stop_loss(price, action, trailing_stop_loss),
      take_profit_price: calculate_take_profit(price)
    )
  end

  def self.calculate_stop_loss(price, action, trailing_stop_loss)
    action == "BUY" ? price - trailing_stop_loss : price + trailing_stop_loss
  end

  def self.calculate_take_profit(price)
    price * 1.02 # 1:2 profit-loss ratio
  end
end
