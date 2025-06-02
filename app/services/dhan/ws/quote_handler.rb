module Dhan
  module Ws
    class QuoteHandler
      def self.call(packet)
        sid = packet[:security_id]
        segment_enum = packet[:exchange_segment]
        segment_key = DhanhqMappings::SEGMENT_ENUM_TO_KEY[segment_enum]
        inst = FeedListener.find_instrument_cached(sid) or return

        cache_key = "ltp_#{segment_key}_#{sid}"
        prev_ltp = Rails.cache.read(cache_key)
        return if prev_ltp == packet[:ltp]

        Rails.cache.write(cache_key, packet[:ltp])
        Rails.cache.write("index_meta_#{segment_key}_#{sid}", {
                            ltp: packet[:ltp],
                            open: packet[:day_open],
                            high: packet[:day_high],
                            low: packet[:day_low],
                            time: Time.zone.now.to_s(:db)
                          })

        Rails.logger.debug do
          "[QUOTE] #{inst.symbol_name} ▶ LTP=#{packet[:ltp]} O/H/L=#{packet[:day_open]}/#{packet[:day_high]}/#{packet[:day_low]}"
        end
      rescue StandardError => e
        Rails.logger.error "[QUOTE] ❌ #{e.class} - #{e.message}"
      end
    end
  end
end
