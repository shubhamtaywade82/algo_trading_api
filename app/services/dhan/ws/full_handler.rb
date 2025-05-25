# File: app/services/dhan/ws/full_handler.rb
# frozen_string_literal: true

module Dhan
  module Ws
    class FullHandler
      # Full packet: code 8
      # bytes[4,4]   = security_id
      # bytes[8,4]   = ltp
      # bytes[12,2]  = ltq
      # bytes[14,4]  = ltt
      # bytes[18,4]  = atp
      # bytes[22,4]  = volume
      # bytes[26,4]  = total_sell_qty
      # bytes[30,4]  = total_buy_qty
      # bytes[34,4]  = oi
      # bytes[38,4]  = high_oi
      # bytes[42,4]  = low_oi
      # bytes[46,4]  = day_open
      # bytes[50,4]  = day_close
      # bytes[54,4]  = day_high
      # bytes[58,4]  = day_low
      # bytes[63..162] = five 20-byte depth entries
      def self.call(bytes)
        sid      = bytes[4, 4].pack('C*').unpack1('L<')
        ltp      = bytes[8, 4].pack('C*').unpack1('e')
        bytes[12, 2].pack('C*').unpack1('S<')
        bytes[14, 4].pack('C*').unpack1('L<')
        bytes[18, 4].pack('C*').unpack1('e')
        vol = bytes[22, 4].pack('C*').unpack1('L<')
        bytes[26, 4].pack('C*').unpack1('L<')
        bytes[30, 4].pack('C*').unpack1('L<')
        oi = bytes[34, 4].pack('C*').unpack1('L<')
        bytes[38, 4].pack('C*').unpack1('L<')
        bytes[42, 4].pack('C*').unpack1('L<')
        bytes[46, 4].pack('C*').unpack1('e')
        bytes[50, 4].pack('C*').unpack1('e')
        bytes[54, 4].pack('C*').unpack1('e')
        bytes[58, 4].pack('C*').unpack1('e')
        inst = Instrument.find_by(security_id: sid) or return
        tick_time = Time.zone.at(bytes[14, 4].pack('C*').unpack1('L<'))

        # market depth: 5 levels × 20 bytes
        levels = Array.new(5) do |i|
          base = 63 + (i * 20)
          bid_qty, ask_qty = bytes[base, 8].pack('C*').unpack('l<l<')
          bid_odrs, ask_odrs = bytes[base + 8, 4].pack('C*').unpack('S<S<')
          bid_pr = bytes[base + 12, 4].pack('C*').unpack1('e')
          ask_pr = bytes[base + 16, 4].pack('C*').unpack1('e')
          {
            bid_qty: bid_qty, ask_qty: ask_qty,
            bid_orders: bid_odrs, ask_orders: ask_odrs,
            bid_price: bid_pr, ask_price: ask_pr
          }
        end

        # persist the main quote
        Quote.create!(
          instrument: inst,
          ltp: ltp,
          volume: vol,
          tick_time: tick_time,
          metadata: { oi: oi, depth: levels }
        )

        Rails.logger.debug { "[FULL] #{inst.symbol_name} ⏩ LTP=#{ltp.round(2)}, VOL=#{vol}, DEPTH=#{levels.inspect}" }
      end
    end
  end
end
