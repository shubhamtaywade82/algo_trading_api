# frozen_string_literal: true

module Dhan
  module Ws
    class QuoteHandler
      def self.call(packet)
        sid = packet[:security_id]
        segment_enum = packet[:exchange_segment]
        segment_key = DhanhqMappings::SEGMENT_ENUM_TO_KEY[segment_enum]

        inst = Instrument.find_by(security_id: sid.to_i) or return

        Rails.logger.debug do
          pp "[QUOTE] #{inst.symbol_name} ⏩ LTP=#{packet[:ltp]} VOL=#{packet[:volume]} O/H/L=#{packet[:day_open]}/#{packet[:day_high]}/#{packet[:day_low]}"
        end

        # Update LTP in Rails.cache for live usage
        Rails.cache.write("ltp_#{segment_key}_#{sid}", packet[:ltp])

        # Optionally: track index movement
        # Rails.cache.write("index_meta_#{segment_key}_#{sid}", {
        #   open: packet[:day_open],
        #   high: packet[:day_high],
        #   low: packet[:day_low],
        #   ltp: packet[:ltp],
        #   time: Time.zone.now
        # })

        # Indexes aren’t tradable, so no Positions::Manager or Orders::Manager call
        # This is purely for real-time monitoring & signal input
      rescue StandardError => e
        Rails.logger.error "[QUOTE] ❌ #{e.class} - #{e.message}"
      end
    end
  end
end
