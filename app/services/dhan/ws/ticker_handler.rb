# File: app/services/dhan/ws/ticker_handler.rb
# frozen_string_literal: true

module Dhan
  module Ws
    class TickerHandler
      # Ticker packet: code 2
      # bytes[4,4]  = security_id (uint32 little)
      # bytes[8,4]  = ltp         (float32 little)
      # bytes[12,4] = ltt         (int32 little)
      def self.call(bytes)
        sid = bytes[4, 4].pack('C*').unpack1('L<')
        ltp = bytes[8, 4].pack('C*').unpack1('e')
        ltt = bytes[12, 4].pack('C*').unpack1('L<')

        Rails.logger.debug { "TickerHandler: sid=#{sid}, ltp=#{ltp}, ltt=#{ltt}" }
        inst = Instrument.find_by(security_id: sid) or return
        tick_time = Time.zone.at(ltt)

        # Persist a minimal quote
        Quote.create!(
          instrument: inst,
          ltp: ltp,
          volume: nil,
          tick_time: tick_time
        )
        Rails.logger.debug { "[TICKER] #{inst.symbol_name} ⏩ LTP=#{ltp.round(2)} at #{tick_time.strftime('%H:%M:%S')}" }
      end
    end
  end
end
