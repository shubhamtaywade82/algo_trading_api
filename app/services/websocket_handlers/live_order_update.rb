require "websocket-client-simple"

class LiveOrderUpdate
  def initialize(token:, client_id:)
    @url = "wss://api-order-update.dhan.co"
    @auth_message = {
      LoginReq: {
        MsgCode: 42,
        ClientId: client_id,
        Token: token
      },
      UserType: "SELF"
    }
  end

  def connect
    @ws = WebSocket::Client::Simple.connect(@url)

    @ws.on(:open) { authenticate }
    @ws.on(:message) { |msg| handle_message(msg) }
  end

  private

  def authenticate
    @ws.send(@auth_message.to_json)
    Rails.logger.info "Order update connection authenticated."
  end

  def handle_message(msg)
    data = JSON.parse(msg.data)
    OrderManagement::OrderProcessor.new(data).process
  end
end
