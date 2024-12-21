module MarketFeed
  module Handlers
    class QuoteHandler
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
          total_sell_quantity: @io.read(4).unpack1("N"),
          total_buy_quantity: @io.read(4).unpack1("N"),
          day_open: @io.read(4).unpack1("F"),
          day_high: @io.read(4).unpack1("F"),
          day_low: @io.read(4).unpack1("F")
        }
      end
    end
  end
end
