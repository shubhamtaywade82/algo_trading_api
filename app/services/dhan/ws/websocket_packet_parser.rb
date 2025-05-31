# frozen_string_literal: true

module Dhan
  module Ws
    class WebsocketPacketParser
      RESPONSE_CODES = {
        ticker: 2,
        prev_close: 6,
        quote: 4,
        oi: 5,
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

        case header[:feed_response_code]
        when RESPONSE_CODES[:ticker]
          header.merge(parse_ticker)
        when RESPONSE_CODES[:prev_close]
          header.merge(parse_prev_close)
        when RESPONSE_CODES[:quote]
          header.merge(parse_quote)
        when RESPONSE_CODES[:oi]
          header.merge(parse_oi)
        when RESPONSE_CODES[:full]
          header.merge(parse_full)
        when RESPONSE_CODES[:disconnect]
          header.merge(parse_disconnect)
        when RESPONSE_CODES[:depth_bid], RESPONSE_CODES[:depth_ask]
          header.merge(parse_depth(header[:feed_response_code]))
        else
          raise "Unknown response code: #{header[:feed_response_code]}"
        end
      end

      private

      def parse_header
        {
          message_length: binary_data.read(2).unpack1('s>'),
          feed_response_code: binary_data.read(1).unpack1('C'),
          exchange_segment: binary_data.read(1).unpack1('C'),
          security_id: binary_data.read(4).unpack1('l>').to_s,
          message_sequence: binary_data.read(4).unpack1('L>')
        }
      end

      def parse_ticker
        {
          ltp: binary_data.read(4).unpack1('g'),
          ltt: binary_data.read(4).unpack1('l>')
        }
      end

      def parse_prev_close
        {
          previous_close: binary_data.read(4).unpack1('g'),
          previous_open_interest: binary_data.read(4).unpack1('l>')
        }
      end

      def parse_quote
        {
          ltp: binary_data.read(4).unpack1('g'),
          last_trade_qty: binary_data.read(2).unpack1('s>'),
          ltt: binary_data.read(4).unpack1('l>'),
          atp: binary_data.read(4).unpack1('g'),
          volume: binary_data.read(4).unpack1('l>'),
          total_sell_qty: binary_data.read(4).unpack1('l>'),
          total_buy_qty: binary_data.read(4).unpack1('l>'),
          day_open: binary_data.read(4).unpack1('g'),
          day_close: binary_data.read(4).unpack1('g'),
          day_high: binary_data.read(4).unpack1('g'),
          day_low: binary_data.read(4).unpack1('g')
        }
      end

      def parse_oi
        {
          open_interest: binary_data.read(4).unpack1('l>')
        }
      end

      def parse_full
        parsed_data = parse_quote

        parsed_data.merge!({
                             open_interest: binary_data.read(4).unpack1('l>'),
                             highest_open_interest: binary_data.read(4).unpack1('l>'),
                             lowest_open_interest: binary_data.read(4).unpack1('l>'),
                             day_open: binary_data.read(4).unpack1('g'),
                             day_close: binary_data.read(4).unpack1('g'),
                             day_high: binary_data.read(4).unpack1('g'),
                             day_low: binary_data.read(4).unpack1('g'),
                             market_depth: parse_market_depth
                           })

        parsed_data
      end

      def parse_market_depth
        Array.new(5) do
          {
            bid_quantity: binary_data.read(4).unpack1('l>'),
            ask_quantity: binary_data.read(4).unpack1('l>'),
            no_of_bid_orders: binary_data.read(2).unpack1('s>'),
            no_of_ask_orders: binary_data.read(2).unpack1('s>'),
            bid_price: binary_data.read(4).unpack1('g'),
            ask_price: binary_data.read(4).unpack1('g')
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
              price: binary_data.read(8).unpack1('G'),
              quantity: binary_data.read(4).unpack1('L>'),
              no_of_orders: binary_data.read(4).unpack1('L>')
            }
          end
        }
      end
    end
  end
end