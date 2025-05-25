# File: app/services/dhan/ws/quote_handler.rb
# frozen_string_literal: true

module Dhan
  module Ws
    class QuoteHandler
      # Quote packet: code 4
      # bytes[4,4]   = security_id
      # bytes[8,4]   = ltp
      # bytes[12,2]  = ltq
      # bytes[14,4]  = ltt
      # bytes[18,4]  = atp
      # bytes[22,4]  = volume
      # bytes[26,4]  = total_sell_qty
      # bytes[30,4]  = total_buy_qty
      # bytes[34,4]  = day_open
      # bytes[38,4]  = day_close
      # bytes[42,4]  = day_high
      # bytes[46,4]  = day_low
      def self.call(bytes)
        sid      = bytes[4, 4].pack('C*').unpack1('L<')
        ltp      = bytes[8, 4].pack('C*').unpack1('e')
        ltq      = bytes[12, 2].pack('C*').unpack1('S<')
        ltt      = bytes[14, 4].pack('C*').unpack1('L<')
        atp      = bytes[18, 4].pack('C*').unpack1('e')
        vol      = bytes[22, 4].pack('C*').unpack1('L<')
        sell_q   = bytes[26, 4].pack('C*').unpack1('L<')
        buy_q    = bytes[30, 4].pack('C*').unpack1('L<')
        open_v   = bytes[34, 4].pack('C*').unpack1('e')
        close_v  = bytes[38, 4].pack('C*').unpack1('e')
        high_v   = bytes[42, 4].pack('C*').unpack1('e')
        low_v    = bytes[46, 4].pack('C*').unpack1('e')

        inst = Instrument.find_by(security_id: sid) or return
        tick_time = Time.at(ltt)

        Quote.create!(
          instrument: inst,
          ltp: ltp,
          volume: vol,
          tick_time: tick_time
        )

        Rails.logger.debug { "[QUOTE] #{inst.symbol_name} ⏩ LTP=#{ltp.round(2)}, LTQ=#{ltq}, VOL=#{vol}" }
      end
    end
  end
end
