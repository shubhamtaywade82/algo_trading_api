# app/services/websocket_handlers/live_order_handler.rb
module WebsocketHandlers
  class LiveOrderHandler
    def initialize(websocket_connection)
      @websocket_connection = websocket_connection
    end

    def process_messages
      @websocket_connection.on(:message) do |message|
        handle_message(JSON.parse(message))
      rescue JSON::ParserError => e
        Rails.logger.error("Invalid JSON received: #{e.message}")
      end
    end

    private

    def handle_message(message)
      if message["Type"] == "order_alert"
        parsed_order = Parsers::LiveOrderParser.new(message).parse
        process_order(parsed_order) if parsed_order
      else
        Rails.logger.info("Unhandled message type: #{message['Type']}")
      end
    end

    def process_order(order_data)
      # Add logic to process the parsed order
      Rails.logger.info("Processing Order: #{order_data}")
      # Example: Update order in database
    end
  end
end
