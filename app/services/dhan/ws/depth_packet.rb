# File: depth_packet.rb
# Defines parsing logic for DhanHQ 20-level depth packets.
module Dhan
  module Ws
    module DepthPacket
      # each depth entry is 16 bytes: float64 price, uint32 qty, uint32 orders
      ENTRY_SIZE = 16

      def self.parse_level(bytes, start_off)
        slice = bytes[start_off, ENTRY_SIZE]
        price = slice[0,8].pack('C*').unpack1('G')  # big-endian float64
        qty   = slice[8,4].pack('C*').unpack1('L<')
        orders= slice[12,4].pack('C*').unpack1('L<')
        { price: price, quantity: qty, orders: orders }
      end

      def self.parse(bytes)
        # header length is 12 bytes, payload starts at offset 12
        offset = 12
        levels = []
        # alternating Bid (code 41) and Ask (code 51)
        2.times do |side_idx|
          level_list = []
          20.times do |i|
            level_list << parse_level(bytes, offset)
            offset += ENTRY_SIZE
          end
          levels << { side: (side_idx.zero? ? :bid : :ask), levels: level_list }
        end
        levels
      end
    end
  end
end