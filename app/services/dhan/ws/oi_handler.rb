# File: app/services/dhan/ws/oi_handler.rb
# frozen_string_literal: true

module Dhan
  module Ws
    class OiHandler
      # OI packet: code 5
      # bytes[4,4]  = security_id
      # bytes[8,4]  = open_interest
      def self.call(bytes)
        packet = Dhanhq::WebsocketPacketParser.new(bytes.pack('C*')).parse
        sid = packet[:security_id]

        inst = Instrument.find_by(security_id: sid) or return
        Rails.logger.debug { "[OI] #{inst.symbol_name} ⏩ OI=#{packet[:open_interest]}" }

        pos = Positions::ActiveCache.fetch(sid) or return
        pos['open_interest'] = packet[:open_interest]
        analysis = Orders::Analyzer.call(pos)
        Orders::Manager.call(pos, analysis)
      end
    end
  end
end
