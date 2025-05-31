# File: app/services/dhan/ws/prev_close_handler.rb
# frozen_string_literal: true

module Dhan
  module Ws
    class PrevCloseHandler
      # PrevClose packet: code 6
      # bytes[4,4]   = security_id
      # bytes[8,4]   = prev_close_price
      # bytes[12,4]  = prev_open_interest
      def self.call(bytes)
        sid        = bytes[4, 4].pack('C*').unpack1('L<')
        prev_close = bytes[8, 4].pack('C*').unpack1('e')
        prev_oi    = bytes[12, 4].pack('C*').unpack1('l<')
        inst = Instrument.find_by(security_id: sid) or return

        # again, adjust to your persistence model if needed
        Rails.logger.debug { "[PREV CLOSE] #{inst.symbol_name} ⏩ PrevClose=#{prev_close.round(2)}, PrevOI=#{prev_oi}" }
      end
    end
  end
end
