module Dhan
  module Ws
    class OiHandler
      def self.call(packet)
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
