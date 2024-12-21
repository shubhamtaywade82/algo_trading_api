# app/services/websocket_handlers/market_feed_handler.rb
require 'faye/websocket'
require 'eventmachine'
require 'json'

module WebsocketHandlers
  class MarketFeedHandler
    def initialize
      @connection = Faye::WebSocket::Client.new("wss://api-feed.dhan.co?version=2&token=#{ENV['DHAN_ACCESS_TOKEN']}&clientId=#{ENV['DHAN_CLIENT_ID']}&authType=2")
    end

    def subscribe_to_instruments(instruments)
      subscription_message = {
        "RequestCode": 15,
        "InstrumentCount": instruments.size,
        "InstrumentList": instruments
      }
      @connection.send(subscription_message.to_json)
    end

    def listen
      @connection.on(:message) do |event|
        handle_market_data(JSON.parse(event.data))
      end
    end

    private

    def handle_market_data(data)
      # Parse and process market feed data
      # Example: Adjust stop-loss or trigger trades
      Rails.logger.info("Market Data Received: #{data}")
    end
  end
end
