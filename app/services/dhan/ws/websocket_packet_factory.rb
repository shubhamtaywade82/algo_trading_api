require_relative 'packets/header'
require_relative 'packets/ticker_packet'
require_relative 'packets/quote_packet'
require_relative 'packets/oi_packet'
require_relative 'packets/prev_close_packet'
require_relative 'packets/full_packet'
require_relative 'packets/depth_packet'

module Dhan
  module Ws
    class WebsocketPacketFactory
      RESPONSE_MAP = {
        2 => Packets::TickerPacket,
        4 => Packets::QuotePacket,
        5 => Packets::OIPacket,
        6 => Packets::PrevClosePacket,
        8 => Packets::FullPacket,
        41 => Packets::DepthPacket,
        51 => Packets::DepthPacket
      }.freeze

      def self.parse(binary_data)
        header = Packets::Header.read(binary_data)

        # Remaining payload after first 8 bytes
        payload = binary_data.byteslice(8..)
        parser_class = RESPONSE_MAP[header.feed_response_code]

        body = parser_class&.read(payload)

        {
          feed_response_code: header.feed_response_code,
          message_length: header.message_length,
          exchange_segment: header.exchange_segment,
          security_id: header.security_id,
          data: body&.to_h
        }
      rescue StandardError => e
        Rails.logger.error "[WS::Factory] ❌ Parse error: #{e.class} - #{e.message}"
        nil
      end
    end
  end
end