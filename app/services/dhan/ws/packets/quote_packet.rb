module Dhan
  module Ws
    module Packets
      class QuotePacket < BinData::Record
        endian :little

        float_le :ltp
        int16   :last_trade_qty
        int32   :ltt
        float_le :atp
        int32   :volume
        int32   :total_sell_qty
        int32   :total_buy_qty
        float_le :day_open
        float_le :day_close
        float_le :day_high
        float_le :day_low
      end
    end
  end
end