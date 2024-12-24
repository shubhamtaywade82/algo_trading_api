# app/services/websocket_handler.rb
require "websocket-client-simple"

class WebSocketHandler
  def self.start_order_updates
    ws = WebSocket::Client::Simple.connect("wss://api-order-update.dhan.co")

    ws.on :open do
      ws.send({ LoginReq: { MsgCode: 42, ClientId: "1000000001", Token: "JWT" }, UserType: "SELF" }.to_json)
    end

    ws.on :message do |msg|
      process_order_update(JSON.parse(msg.data))
    end
  end

  def self.process_order_update(update)
    order = Order.find_by(dhan_order_id: update["Data"]["OrderNo"])
    return unless order

    order.update(
      dhan_status: update["Data"]["Status"],
      traded_price: update["Data"]["TradedPrice"],
      remaining_quantity: update["Data"]["RemainingQuantity"]
    )
  end
end
