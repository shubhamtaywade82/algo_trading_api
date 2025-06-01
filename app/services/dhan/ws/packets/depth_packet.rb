module Dhan
  module Ws
    module Packets
      class DepthPacketLevel < BinData::Record
        endian :little

        float64 :price       # 8 bytes
        uint32  :quantity    # 4 bytes
        uint32  :no_of_orders # 4 bytes
      end

      class DepthPacket < BinData::Record
        endian :little

        array :depth_levels, initial_length: 20 do
          depth_packet_level
        end
      end
    end
  end
end