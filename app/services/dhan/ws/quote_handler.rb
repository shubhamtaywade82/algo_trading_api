# frozen_string_literal: true

module Dhan
  module Ws
    class QuoteHandler
      def self.call(packet)
        sid = packet[:security_id]
        segment_enum = packet[:exchange_segment]
        segment_key = DhanhqMappings::SEGMENT_ENUM_TO_KEY[segment_enum]
        inst = FeedListener.find_instrument_cached(sid, segment_enum) or return

        MarketCache.write_ltp(segment_key, sid, packet[:ltp])

        MarketCache.write_market_data(segment_key, sid, {
                                        ltp: packet[:ltp],
                                        volume: packet[:volume],
                                        day_open: packet[:day_open],
                                        day_high: packet[:day_high],
                                        day_low: packet[:day_low],
                                        day_close: packet[:day_close],
                                        time: Time.zone.now
                                      })

        # Rails.logger.debug do
        #   # pp "[QUOTE] #{inst.symbol_name} ▶ LTP=#{packet[:ltp]} O/H/L=#{packet[:day_open]}/#{packet[:day_high]}/#{packet[:day_low]}"
        # end
      rescue StandardError => e
        Rails.logger.error "[QUOTE] ❌ #{e.class} - #{e.message}"
      end
    end
  end
end
