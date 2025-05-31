module Dhan
  module Ws
    module Packets
      class PrevClosePacket < BinData::Record
        endian :little

        float32 :previous_close        # Bytes 9–12
        int32   :previous_oi           # Bytes 13–16
      end
    end
  end
end