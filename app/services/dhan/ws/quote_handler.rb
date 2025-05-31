module Dhan
  module Ws
    class QuoteHandler
      def self.call(packet)
        sid = packet[:security_id]
        inst = Instrument.find_by(security_id: sid) or return

        Quote.create!(
          instrument: inst,
          ltp: packet[:ltp],
          volume: packet[:volume],
          tick_time: Time.zone.at(packet[:ltt])
        )

        pos = Positions::ActiveCache.fetch(sid) or return
        pos['ltp'] = packet[:ltp]
        analysis = Orders::Analyzer.call(pos)
        Orders::Manager.call(pos, analysis)
      end
    end
  end
end
