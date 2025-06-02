# frozen_string_literal: true

module Dhan
  module Ws
    class FullHandler
      def self.call(packet)
        sid = packet[:security_id]
        segment_enum = packet[:exchange_segment]
        segment_key = DhanhqMappings::SEGMENT_ENUM_TO_KEY[segment_enum]
        inst = FeedListener.find_instrument_cached(sid) or return

        cache_key = "ltp_#{segment_key}_#{sid}"
        prev_ltp = Rails.cache.read(cache_key)
        return if prev_ltp == packet[:ltp] # No change in price, skip heavy ops

        Rails.cache.write(cache_key, packet[:ltp])
        Rails.cache.write("depth_#{segment_key}_#{sid}", packet[:market_depth])

        Rails.logger.debug do
          "[FULL] #{inst.symbol_name} ▶ LTP=#{packet[:ltp]} VOL=#{packet[:volume]}"
        end

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
