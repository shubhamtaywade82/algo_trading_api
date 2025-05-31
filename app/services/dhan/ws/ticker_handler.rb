# File: app/services/dhan/ws/ticker_handler.rb
# frozen_string_literal: true

module Dhan
  module Ws
    class TickerHandler
      def self.call(bytes)
        packet = Dhanhq::WebsocketPacketParser.new(bytes.pack('C*')).parse
        sid = packet[:security_id]
        ltp = packet[:ltp]
        ltt = packet[:ltt]

        inst = Instrument.find_by(security_id: sid) or return
        Quote.create!(instrument: inst, ltp: ltp, tick_time: Time.zone.at(ltt))
        pos = Positions::ActiveCache.fetch(sid) or return
        pos['ltp'] = ltp
        analysis = Orders::Analyzer.call(pos)
        Orders::Manager.call(pos, analysis)
      end
    end
  end
end
