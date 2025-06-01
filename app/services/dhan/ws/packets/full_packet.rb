require_relative 'market_depth_level'

module Dhan
  module Ws
    module Packets
      class FullPacket < BinData::Record
        endian :little

        double_le :ltp
        int16   :last_trade_qty
        int32   :ltt
        float_le :atp
        int32   :volume
        int32   :total_sell_qty
        int32   :total_buy_qty
        int32   :open_interest
        int32   :highest_oi
        int32   :lowest_oi
        float_le :day_open
        float_le :day_close
        float_le :day_high
        float_le :day_low

        array :market_depth, initial_length: 5 do
          market_depth_level
        end
      end
    end
  end
end