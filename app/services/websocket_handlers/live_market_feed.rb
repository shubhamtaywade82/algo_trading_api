require "websocket-client-simple"

class LiveMarketFeed
  def initialize(token:, client_id:)
    @url = "wss://api-feed.dhan.co?version=2&token=#{token}&clientId=#{client_id}&authType=2"
    @subscribed_instruments = []
  end

  def connect
    @ws = WebSocket::Client::Simple.connect(@url)

    @ws.on(:message) do |msg|
      pp msg.data
    end
    @ws.on(:open)    { Rails.logger.info "Market feed connection established." }
    @ws.on(:close)   { Rails.logger.warn "Market feed connection closed." }
    @ws.on(:error)   { |err| Rails.logger.error "Market feed error: #{err.message}" }
  end

  def subscribe_to_instruments(instruments)
    instruments.each_slice(100) do |batch|
      message = {
        RequestCode: 15,
        InstrumentCount: batch.size,
        InstrumentList: batch.map { |inst| { ExchangeSegment: inst[:exchange_segment], SecurityId: inst[:security_id] } }
      }
      @ws.send(message.to_json)
    end
    @subscribed_instruments += instruments
  end

  private

  def handle_message(msg)
    begin
      data = JSON.parse(msg.data)
      MarketFeed::DataProcessor.new(data).process
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse market feed message: #{msg.data}. Error: #{e.message}"
    rescue StandardError => e
      Rails.logger.error "Error processing market feed message: #{e.message}"
    end
  end
end
