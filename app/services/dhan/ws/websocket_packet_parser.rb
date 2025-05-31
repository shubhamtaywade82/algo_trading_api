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

      attr_reader :binary_data

      def initialize(binary_data)
        @binary_data = StringIO.new(binary_data)
      end

      def parse
        header = parse_header

        data = case header[:feed_response_code]
               when RESPONSE_CODES[:ticker]       then parse_ticker
               when RESPONSE_CODES[:quote]        then parse_quote
               when RESPONSE_CODES[:oi]           then parse_oi
               when RESPONSE_CODES[:prev_close]   then parse_prev_close
               when RESPONSE_CODES[:full]         then parse_full
               when RESPONSE_CODES[:disconnect]   then parse_disconnect
               when RESPONSE_CODES[:depth_bid],
                    RESPONSE_CODES[:depth_ask] then parse_depth(header[:feed_response_code])
               else
                 raise "Unknown response code: #{header[:feed_response_code]}"
               end

        full_data = header.merge(data)

        debug_log(full_data)
        full_data
      rescue StandardError => e
        Rails.logger.error "[WS::Parser] ❌ #{e.class}: #{e.message}"
        {}
      end

      private

      def parse_header

        pp binary_data.read(1).unpack1('C') # Ensure we start reading from the beginning
        pp binary_data.read(2).unpack1('s>')
        pp binary_data.read(1).unpack1('C')
        pp binary_data.read(4).unpack1('L>')
        {
          feed_response_code: binary_data.read(1).unpack1('C'), # byte 0
          message_length: binary_data.read(2).unpack1('s>'), # bytes 1-2
          exchange_segment: binary_data.read(1).unpack1('C'), # byte 3
          security_id: binary_data.read(4).unpack1('L>') # bytes 4-7
        }
      end

      def parse_ticker
        {
          ltp: binary_data.read(4).unpack1('e'),
          ltt: binary_data.read(4).unpack1('l>')
        }
      end

      def parse_prev_close
        {
          previous_close: binary_data.read(4).unpack1('e'),
          previous_open_interest: binary_data.read(4).unpack1('l>')
        }
      end

      def parse_quote
        {
          ltp: binary_data.read(4).unpack1('e'),
          last_trade_qty: binary_data.read(2).unpack1('s>'),
          ltt: binary_data.read(4).unpack1('l>'),
          atp: binary_data.read(4).unpack1('e'),
          volume: binary_data.read(4).unpack1('l>'),
          total_sell_qty: binary_data.read(4).unpack1('l>'),
          total_buy_qty: binary_data.read(4).unpack1('l>'),
          day_open: binary_data.read(4).unpack1('e'),
          day_close: binary_data.read(4).unpack1('e'),
          day_high: binary_data.read(4).unpack1('e'),
          day_low: binary_data.read(4).unpack1('e')
        }
      end

      def parse_oi
        {
          open_interest: binary_data.read(4).unpack1('l>')
        }
      end

      def parse_full
        quote_data = {
          ltp: binary_data.read(4).unpack1('e'),
          last_trade_qty: binary_data.read(2).unpack1('s>'),
          ltt: binary_data.read(4).unpack1('l>'),
          atp: binary_data.read(4).unpack1('e'),
          volume: binary_data.read(4).unpack1('l>'),
          total_sell_qty: binary_data.read(4).unpack1('l>'),
          total_buy_qty: binary_data.read(4).unpack1('l>')
        }

        additional_data = {
          open_interest: binary_data.read(4).unpack1('l>'),
          highest_open_interest: binary_data.read(4).unpack1('l>'),
          lowest_open_interest: binary_data.read(4).unpack1('l>'),
          day_open: binary_data.read(4).unpack1('e'),
          day_close: binary_data.read(4).unpack1('e'),
          day_high: binary_data.read(4).unpack1('e'),
          day_low: binary_data.read(4).unpack1('e'),
          market_depth: parse_market_depth
        }

        quote_data.merge(additional_data)
      end

      def parse_market_depth
        Array.new(5) do
          {
            bid_quantity: binary_data.read(4).unpack1('l>'),
            ask_quantity: binary_data.read(4).unpack1('l>'),
            no_of_bid_orders: binary_data.read(2).unpack1('s>'),
            no_of_ask_orders: binary_data.read(2).unpack1('s>'),
            bid_price: binary_data.read(4).unpack1('e'),
            ask_price: binary_data.read(4).unpack1('e')
          }
        end
      end

      def parse_disconnect
        {
          disconnection_code: binary_data.read(2).unpack1('s>')
        }
      end

      def parse_depth(response_code)
        {
          depth_type: response_code == RESPONSE_CODES[:depth_bid] ? 'bid' : 'ask',
          depth_levels: Array.new(20) do
            {
              price: binary_data.read(8).unpack1('E'), # float64 little-endian
              quantity: binary_data.read(4).unpack1('L>'),
              no_of_orders: binary_data.read(4).unpack1('L>')
            }
          end
        }
      end

      def debug_log(data)
        pp "[WS::Parser] Parsed: #{data.inspect}" if ENV['DEBUG_WS'] == 'true'
      end
    end
  end
end
