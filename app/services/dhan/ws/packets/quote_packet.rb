module Dhan
  module Ws
    module Packets
      class QuotePacket < BinData::Record
        endian :little

        float32 :ltp
        int16   :last_trade_qty
        int32   :ltt
        float32 :atp
        int32   :volume
        int32   :total_sell_qty
        int32   :total_buy_qty
        float32 :day_open
        float32 :day_close
        float32 :day_high
        float32 :day_low
      end
    end
  end
end