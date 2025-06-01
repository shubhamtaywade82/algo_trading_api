module Dhan
  module Ws
    module Packets
      class OIPacket < BinData::Record
        endian :little

        int32 :open_interest # Bytes 9–12
      end
    end
  end
end