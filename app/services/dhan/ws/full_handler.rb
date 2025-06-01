# frozen_string_literal: true

module Dhan
  module Ws
    class FullHandler
      def self.call(packet)

        sid = packet[:security_id]
        inst = Instrument.find_by(security_id: sid.to_i) or return

        # tick_time = Time.zone.at(packet[:ltt])

        # Quote.create!(
        #   instrument: inst,
        #   ltp: packet[:ltp],
        #   volume: packet[:volume],
        #   tick_time: tick_time,
        #   metadata: {
        #     oi: packet[:open_interest],
        #     depth: packet[:market_depth]
        #   }
        # )

        Rails.logger.debug do
          pp "[FULL] #{inst.symbol_name} ⏩ LTP=#{packet[:ltp]} VOL=#{packet[:volume]} DEPTH=#{packet[:market_depth].inspect}"
        end

        pos = Positions::ActiveCache.fetch(sid)
        return unless pos

        pos['ltp'] = packet[:ltp]
        pos['depth'] = packet[:market_depth]

        analysis = Orders::Analyzer.call(pos)
        Orders::Manager.call(pos, analysis)
      rescue StandardError => e
        Rails.logger.error "[FULL] ❌ #{e.class} - #{e.message}"
      end
    end
  end
end
