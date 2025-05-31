module Dhan
  module Ws
    module Packets
      class TickerPacket < BinData::Record
        endian :little

        float32 :ltp               # Bytes 9–12
        int32   :ltt               # Bytes 13–16
      end
    end
  end
end