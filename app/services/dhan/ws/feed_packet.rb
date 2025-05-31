# frozen_string_literal: true

module Dhan
  module Ws
    module FeedPacket
      # Unpacks a 4-byte little-endian unsigned int from `bytes` at offset `off`
      def self.uint32(bytes, off)
        bytes[off, 4].pack('C*').unpack1('L<')
      end

      # Unpacks a 2-byte little-endian unsigned int from `bytes` at `off`
      def self.uint16(bytes, off)
        bytes[off, 2].pack('C*').unpack1('S<')
      end

      # Unpacks a 4-byte little-endian float32 from `bytes` at offset `off`
      def self.float32(bytes, off)
        bytes[off, 4].pack('C*').unpack1('e')
      end
    end
  end
end
