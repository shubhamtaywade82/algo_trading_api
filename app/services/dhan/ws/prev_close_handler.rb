# File: app/services/dhan/ws/prev_close_handler.rb
# frozen_string_literal: true

module Dhan
  module Ws
    class PrevCloseHandler
      def self.call(bytes)
        packet = Dhanhq::WebsocketPacketParser.new(bytes.pack('C*')).parse
        sid = packet[:security_id]

        inst = Instrument.find_by(security_id: sid) or return
        Rails.logger.debug do
          "[PREV CLOSE] #{inst.symbol_name} ⏩ PrevClose=#{packet[:previous_close]}, PrevOI=#{packet[:previous_open_interest]}"
        end

        pos = Positions::ActiveCache.fetch(sid) or return
        pos['prev_close'] = packet[:previous_close]
        analysis = Orders::Analyzer.call(pos)
        Orders::Manager.call(pos, analysis)
      end
    end
  end
end
