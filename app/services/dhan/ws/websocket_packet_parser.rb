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

      attr_reader :binary_data, :binary_stream

      def initialize(binary_data)
        @binary_data = binary_data
      end

      def parse
        header = Packets::Header.read(@binary_data)

        @binary_stream = StringIO.new(@binary_data.byteslice(8..)) # slice remaining
        body = case header.feed_response_code
               when RESPONSE_CODES[:ticker]       then parse_ticker
               when RESPONSE_CODES[:quote]        then parse_quote
               when RESPONSE_CODES[:oi]           then parse_oi
               when RESPONSE_CODES[:prev_close]   then parse_prev_close
               when RESPONSE_CODES[:full]         then parse_full
               when RESPONSE_CODES[:disconnect]   then parse_disconnect
               when RESPONSE_CODES[:depth_bid],
                    RESPONSE_CODES[:depth_ask] then parse_depth(binary_stream, header.feed_response_code)
               else
                 raise "Unknown response code: #{header.feed_response_code}"
               end

        full_data = {
          feed_response_code: header.feed_response_code,
          message_length: header.message_length,
          exchange_segment: header.exchange_segment,
          security_id: header.security_id
        }.merge(body)

        debug_log(full_data)
        full_data
      rescue StandardError => e
        Rails.logger.error "[WS::Parser] ❌ #{e.class}: #{e.message}"
        {}
      end

      private

      def parse_header
        {
          feed_response_code: binary_stream.read(1).unpack1('C'), # byte 0
          message_length: binary_stream.read(2).unpack1('s>'), # bytes 1-2
          exchange_segment: binary_stream.read(1).unpack1('C'), # byte 3
          security_id: binary_stream.read(4).unpack1('L>'), # bytes 4-7,
          ltp: binary_stream.read(4).unpack1('e'),
          ltt: binary_stream.read(4).unpack1('l>')
        }
      end

      def parse_prev_close
        {
          previous_close: binary_stream.read(4).unpack1('e'),
          previous_open_interest: binary_stream.read(4).unpack1('l>')
        }
      end

      def parse_quote
        {
          ltp: binary_stream.read(4).unpack1('e'),
          last_trade_qty: binary_stream.read(2).unpack1('s>'),
          ltt: binary_stream.read(4).unpack1('l>'),
          atp: binary_stream.read(4).unpack1('e'),
          volume: binary_stream.read(4).unpack1('L>'),
          total_sell_qty: binary_stream.read(4).unpack1('l>'),
          total_buy_qty: binary_stream.read(4).unpack1('l>'),
          day_open: binary_stream.read(4).unpack1('e'),
          day_close: binary_stream.read(4).unpack1('e'),
          day_high: binary_stream.read(4).unpack1('e'),
          day_low: binary_stream.read(4).unpack1('e')
        }
      end

      def parse_oi
        {
          open_interest: binary_stream.read(4).unpack1('l>')
        }
      end

      def parse_full
        header = Packets::Header.read(binary_data)
        return unless header.feed_response_code == 8

        body = Packets::FullPacket.read(binary_data[8..]) # Slice after header

        pp body
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
          market_depth: body.market_depth.map(&:to_h)
        }
      rescue StandardError => e
        Rails.logger.error "[WS::Parser] ❌ #{e.class}: #{e.message}"
        {}
      end

      def parse_market_depth
        Array.new(5) do
          {
            bid_quantity: binary_stream.read(4).unpack1('L>'),
            ask_quantity: binary_stream.read(4).unpack1('L>'),
            no_of_bid_orders: binary_stream.read(2).unpack1('s>'),
            no_of_ask_orders: binary_stream.read(2).unpack1('s>'),
            bid_price: binary_stream.read(4).unpack1('e'),
            ask_price: binary_stream.read(4).unpack1('e')
          }
        end
      end

      def parse_disconnect
        {
          disconnection_code: binary_stream.read(2).unpack1('s>')
        }
      end

      def parse_depth(response_code)
        {
          depth_type: response_code == RESPONSE_CODES[:depth_bid] ? 'bid' : 'ask',
          depth_levels: Array.new(20) do
            {
              price: binary_stream.read(8).unpack1('E'), # float64 little-endian
              quantity: binary_stream.read(4).unpack1('L>'),
              no_of_orders: binary_stream.read(4).unpack1('L>')
            }
          end
        }
      end

      def debug_log(data)
        pp { "[WS::Parser] Parsed: #{data.inspect}" } if ENV['DEBUG_WS'] == 'true'
      end
    end
  end
end
