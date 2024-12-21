module MarketFeed
  module Handlers
    class FullPacketHandler
      def initialize(io)
        @io = io
      end

      def parse_payload
        {
          last_traded_price: @io.read(4).unpack1("F"),
          last_traded_quantity: @io.read(2).unpack1("n"),
          last_traded_time: @io.read(4).unpack1("N"),
          average_trade_price: @io.read(4).unpack1("F"),
          volume: @io.read(4).unpack1("N"),
          open_interest: @io.read(4).unpack1("N"),
          day_high: @io.read(4).unpack1("F"),
          day_low: @io.read(4).unpack1("F"),
          market_depth: parse_market_depth
        }
      end

      private

      def parse_market_depth
        Array.new(5) do
          {
            bid_quantity: @io.read(4).unpack1("N"),
            ask_quantity: @io.read(4).unpack1("N"),
            bid_orders: @io.read(2).unpack1("n"),
            ask_orders: @io.read(2).unpack1("n"),
            bid_price: @io.read(4).unpack1("F"),
            ask_price: @io.read(4).unpack1("F")
          }
        end
      end
    end
  end
end
