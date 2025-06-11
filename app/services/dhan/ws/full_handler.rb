# frozen_string_literal: true

module Dhan
  module Ws
    class FullHandler
      def self.call(packet)
        sid = packet[:security_id]
        segment_enum = packet[:exchange_segment]
        segment_key = DhanhqMappings::SEGMENT_ENUM_TO_KEY[segment_enum]
        inst = FeedListener.find_instrument_cached(sid, segment_enum) or return

        # Write to cache only if LTP changed
        MarketCache.write_ltp(segment_key, sid, packet[:ltp])

        # Write full market metadata
        MarketCache.write_market_data(segment_key, sid, {
                                        ltp: packet[:ltp],
                                        volume: packet[:volume],
                                        oi: packet[:open_interest],
                                        day_open: packet[:day_open],
                                        day_high: packet[:day_high],
                                        day_low: packet[:day_low],
                                        day_close: packet[:day_close],
                                        atp: packet[:atp],
                                        last_trade_qty: packet[:last_trade_qty],
                                        ltt: packet[:ltt],
                                        depth: packet[:market_depth],
                                        time: Time.zone.at(packet[:ltt])
                                      })

        Rails.logger.debug do
          # pp "[FULL] #{inst.symbol_name} ▶ LTP=#{packet[:ltp]} VOL=#{packet[:volume]}"
        end

        # Run position analysis only if there's an active position
        pos = Positions::ActiveCache.fetch(sid, segment_key)
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
