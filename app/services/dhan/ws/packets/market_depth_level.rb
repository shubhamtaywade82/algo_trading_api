module Dhan
  module Ws
    module Packets
      class MarketDepthLevel < BinData::Record
        endian :little

        int32   :bid_quantity
        int32   :ask_quantity
        int16   :no_of_bid_orders
        int16   :no_of_ask_orders
        float32 :bid_price
        float32 :ask_price
      end
    end
  end
end