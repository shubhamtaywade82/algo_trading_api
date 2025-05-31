# File: app/services/dhan/ws/oi_handler.rb
# frozen_string_literal: true

module Dhan
  module Ws
    class OIHandler
      # OI packet: code 5
      # bytes[4,4]  = security_id
      # bytes[8,4]  = open_interest
      def self.call(bytes)
        sid = bytes[4, 4].pack('C*').unpack1('L<')
        oi  = bytes[8, 4].pack('C*').unpack1('L<')
        inst = Instrument.find_by(security_id: sid) or return

        # you might persist this into a separate model; for now just log
        Rails.logger.debug { "[OI] #{inst.symbol_name} ⏩ OI=#{oi}" }
      end
    end
  end
end
