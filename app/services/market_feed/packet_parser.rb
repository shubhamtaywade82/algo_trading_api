module MarketFeed
  class PacketParser
    def self.parse(binary_data)
      # Convert binary data into a readable format
      io = StringIO.new(binary_data)

      # Parse the Response Header
      response_code = io.read(1).unpack1("C") # Unsigned char
      message_length = io.read(2).unpack1("n") # Unsigned 16-bit (big-endian)
      exchange_segment = io.read(1).unpack1("C") # Unsigned char
      security_id = io.read(4).unpack1("N") # Unsigned 32-bit (big-endian)

      # Fetch Payload Handler
      handler = handler_for_response_code(response_code)
      payload = handler ? handler.new(io).parse_payload : nil

      {
        response_code: response_code,
        message_length: message_length,
        exchange_segment: exchange_segment,
        security_id: security_id,
        payload: payload
      }
    end

    def self.handler_for_response_code(response_code)
      case response_code
      when 2
        Handlers::TickerHandler
      when 4
        Handlers::QuoteHandler
      when 8
        Handlers::FullPacketHandler
      else
        nil # Unknown handler
      end
    end
  end
end
