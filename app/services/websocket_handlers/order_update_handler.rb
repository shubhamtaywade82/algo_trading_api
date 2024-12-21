# app/services/websocket_handlers/order_update_handler.rb
require 'faye/websocket'
require 'eventmachine'
require 'json'
module WebsocketHandlers
  class OrderUpdateHandler
    def initialize
      @connection = Faye::WebSocket::Client.new("wss://api-order-update.dhan.co")
      authenticate
    end

    def authenticate
      auth_message = {
        "LoginReq": {
          "MsgCode": 42,
          "ClientId": ENV["DHAN_CLIENT_ID"],
          "Token": ENV["DHAN_TOKEN"]
        },
        "UserType": "SELF"
      }
      @connection.send(auth_message.to_json)
    end

    def listen
      @connection.on(:message) do |event|
        handle_order_update(JSON.parse(event.data))
      end
    end

    private

    def handle_order_update(data)
      # Parse and process order updates
      Rails.logger.info("Order Update Received: #{data}")
    end
  end
end
