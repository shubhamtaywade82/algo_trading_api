# frozen_string_literal: true

module Dhan
  module Ws
    class WebsocketPacketParser
      RESPONSE_CODES = {
        ticker: 2,
        quote: 4,
        oi: 5,
        prev_close: 6,
        full: 8,
        disconnect: 50,
        depth_bid: 41,
        depth_ask: 51
      }.freeze

      attr_reader :binary_data, :binary_stream, :header

      def initialize(binary_data)
        @binary_data = binary_data
        @header = Packets::Header.read(@binary_data)
        @binary_stream = StringIO.new(@binary_data.byteslice(8..)) # slice remaining
      end

      def parse
        body = case header.feed_response_code
               when RESPONSE_CODES[:full]         then parse_full
               when RESPONSE_CODES[:disconnect]   then parse_disconnect
               else
                 raise "Unknown response code: #{header.feed_response_code}"
               end

        {
          feed_response_code: header.feed_response_code,
          message_length: header.message_length,
          exchange_segment: header.exchange_segment,
          security_id: header.security_id
        }.merge(body)
      rescue StandardError => e
        Rails.logger.error "[WS::Parser] ❌ #{e.class}: #{e.message}"
        {}
      end

      private

      def parse_full
        header = Packets::Header.read(binary_data)
        return unless header.feed_response_code == 8

        body = Packets::FullPacket.read(binary_data[8..]) # Slice after header

        {
          feed_response_code: header.feed_response_code,
          message_length: header.message_length,
          exchange_segment: header.exchange_segment,
          security_id: header.security_id,
          ltp: body.ltp,
          last_trade_qty: body.last_trade_qty,
          ltt: body.ltt,
          atp: body.atp,
          volume: body.volume,
          total_sell_qty: body.total_sell_qty,
          total_buy_qty: body.total_buy_qty,
          open_interest: body.open_interest,
          highest_open_interest: body.highest_oi,
          lowest_open_interest: body.lowest_oi,
          day_open: body.day_open,
          day_close: body.day_close,
          day_high: body.day_high,
          day_low: body.day_low,
          market_depth: body.market_depth
        }
      rescue StandardError => e
        Rails.logger.error "[WS::Parser] ❌ #{e.class}: #{e.message}"
      end

      def parse_disconnect
        {
          disconnection_code: binary_stream.read(2).unpack1('s>')
        }
      end

      def debug_log(data)
        pp "[WS::Parser] Parsed: #{data.inspect}"
      end
    end
  end
end
