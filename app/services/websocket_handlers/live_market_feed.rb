require "faye/websocket"
require "eventmachine"
require "json"

class LiveMarketFeed
  MAX_INSTRUMENTS_PER_BATCH = 100

  def initialize
    @url = build_url
    @subscribed_instruments = []
  end

  def connect
    EM.run do
      @ws = Faye::WebSocket::Client.new(@url)

      @ws.on(:open) do |_event|
        Rails.logger.info "[LiveMarketFeed] WebSocket connection established."
      end

      @ws.on(:message) do |event|
        handle_message(event.data)
      end

      @ws.on(:close) do |event|
        Rails.logger.warn "[LiveMarketFeed] WebSocket connection closed: Code=#{event.code}, Reason=#{event.reason}"
        EM.stop
      end

      @ws.on(:error) do |event|
        Rails.logger.error "[LiveMarketFeed] WebSocket encountered an error: #{event.message}"
      end
    end
  end

  def subscribe_to_instruments(instruments)
    instruments.each_slice(MAX_INSTRUMENTS_PER_BATCH) do |batch|
      subscription_message = {
        RequestCode: 15,
        InstrumentCount: batch.size,
        InstrumentList: batch.map do |inst|
          { ExchangeSegment: inst[:exchange_segment], SecurityId: inst[:security_id] }
        end
      }

      send_message(subscription_message)
    end

    @subscribed_instruments.concat(instruments)
    Rails.logger.info "[LiveMarketFeed] Subscribed to #{instruments.size} instruments."
  end

  def unsubscribe_all
    send_message({ RequestCode: 16 })
    @subscribed_instruments.clear
    Rails.logger.info "[LiveMarketFeed] Unsubscribed from all instruments."
  end

  private

  def build_url
    token = ENV.fetch("DHAN_ACCESS_TOKEN")
    client_id = ENV.fetch("DHAN_CLIENT_ID")
    "wss://api-feed.dhan.co?version=2&token=#{token}&clientId=#{client_id}&authType=2"
  end

  def send_message(message)
    if @ws
      @ws.send(message.to_json)
      Rails.logger.info "[LiveMarketFeed] Sent message: #{message}"
    else
      Rails.logger.error "[LiveMarketFeed] WebSocket connection not established. Cannot send message."
    end
  end

  def handle_message(data)
    begin
      # Market feed messages are in binary and need to be parsed
      parsed_data = MarketFeed::PacketParser.parse(data)
      MarketFeed::DataProcessor.new(parsed_data).process
    rescue JSON::ParserError => e
      Rails.logger.error "[LiveMarketFeed] Failed to parse message: #{e.message}. Raw data: #{data}"
    rescue StandardError => e
      Rails.logger.error "[LiveMarketFeed] Error processing message: #{e.message}"
    end
  end
end
