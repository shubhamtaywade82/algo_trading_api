# frozen_string_literal: true

module MarketFeed
  module Handlers
    class TickerHandler
      def initialize(io)
        @io = io
      end

      def parse_payload
        {
          last_traded_price: @io.read(4).unpack1('F'), # Float
          last_traded_time: @io.read(4).unpack1('N')   # Unsigned 32-bit
        }
      end
    end
  end
end
