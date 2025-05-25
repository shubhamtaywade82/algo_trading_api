# frozen_string_literal: true

# # File: app/services/dhan/ws/feed_listener.rb
# # frozen_string_literal: true

# require 'faye/websocket'
# require 'eventmachine'
# require 'json'

# module Dhan
#   module Ws
#     class FeedListener
#       FEED_URL = [
#         'wss://api-feed.dhan.co?version=2',
#         "token=#{ENV.fetch('DHAN_ACCESS_TOKEN')}",
#         "clientId=#{ENV.fetch('DHAN_CLIENT_ID')}",
#         'authType=2'
#       ].join('&').freeze

#       def self.run
#         EM.run do
#           puts "[WS] Connecting to #{FEED_URL}"
#           ws = Faye::WebSocket::Client.new(FEED_URL)

#           ws.on(:open) do
#             puts '[WS] ▶ Connected'
#             subscribe_all_scripts(ws)
#           end

#           ws.on(:message) do |e|
#             if e.type == :binary
#               parse_binary(e.data)
#             else
#               puts "[WS] ← Text: #{e.data}"
#             end
#           end

#           ws.on(:close) do |e|
#             puts "[WS] ✖ Closed (#{e.code}) #{e.reason} — reconnecting"
#             EM.stop
#             run
#           end

#           ws.on(:error) do |e|
#             puts "[WS] ⚠ Error: #{e.message}"
#           end
#         end
#       end

#       # Subscribe up to 5000 instruments, 100 per JSON payload
#       def self.subscribe_all_scripts(ws)
#         Instrument.segment_equity.pluck(:security_id)
#                   .each_slice(100) do |batch|
#           ws.send({
#             RequestCode:     15,
#             InstrumentCount: batch.size,
#             InstrumentList:  batch.map { |id| { ExchangeSegment: 'NSE_EQ', SecurityId: id } }
#           }.to_json)
#         end
#       end

#       # Top-level demux
#       def self.parse_binary(data)
#         buf  = data.unpack('C*').pack('C*')  # ensure Ruby String
#         code = buf.unpack1('C')              # first byte

#         case code
#         when 2  then handle_ticker(buf)
#         when 4  then handle_quote(buf)
#         when 5  then handle_oi(buf)
#         when 6  then handle_prev_close(buf)
#         when 8  then handle_full(buf)
#         when 50 then handle_disconnect(buf)
#         else
#           puts "[WS] Ignored unknown code #{code}"
#         end
#       rescue => e
#         puts "[WS PARSE ERROR] #{e.class}: #{e.message}"
#       end

#       # 2: Ticker Packet (LTP, LTT)
#       def self.handle_ticker(buf)
#         sid = buf.unpack1('x4L<')
#         ltp = buf.unpack1('x8e')
#         ltt = buf.unpack1('x12L<')
#         inst = Instrument.find_by(security_id: sid) or return
#         puts "[TICKER] #{inst.symbol_name} LTP=#{ltp.round(2)}, Time=#{Time.at(ltt).strftime('%H:%M:%S')}"
#       end

#       # 4: Quote Packet (LTP, LTQ, LTT, ATP, Vol, SellQ, BuyQ, O, C, H, L)
#       def self.handle_quote(buf)
#         sid       = buf.unpack1('x4L<')
#         ltp       = buf.unpack1('x8e')
#         ltq       = buf.unpack1('x12S<')
#         ltt       = buf.unpack1('x14L<')
#         atp       = buf.unpack1('x18e')
#         vol       = buf.unpack1('x22L<')
#         sell_q    = buf.unpack1('x26L<')
#         buy_q     = buf.unpack1('x30L<')
#         open_v    = buf.unpack1('x34e')
#         close_v   = buf.unpack1('x38e')
#         high_v    = buf.unpack1('x42e')
#         low_v     = buf.unpack1('x46e')
#         inst = Instrument.find_by(security_id: sid) or return

#         Quote.create!(
#           instrument: inst,
#           ltp:         ltp,
#           volume:      vol,
#           tick_time:   Time.at(ltt)
#         )

#         puts "[QUOTE] #{inst.symbol_name} LTP=#{ltp.round(2)} LTQ=#{ltq} VOL=#{vol}"
#       end

#       # 5: OI Packet (Open Interest)
#       def self.handle_oi(buf)
#         sid = buf.unpack1('x4L<')
#         oi  = buf.unpack1('x8L<')
#         inst = Instrument.find_by(security_id: sid) or return
#         puts "[OI] #{inst.symbol_name} OI=#{oi}"
#       end

#       # 6: Prev Close Packet (PrevClose, PrevOI)
#       def self.handle_prev_close(buf)
#         sid        = buf.unpack1('x4L<')
#         prev_close = buf.unpack1('x8e')
#         prev_oi    = buf.unpack1('x12l<')
#         inst = Instrument.find_by(security_id: sid) or return
#         puts "[PREV CLOSE] #{inst.symbol_name} PrevClose=#{prev_close.round(2)} PrevOI=#{prev_oi}"
#       end

#       # 8: Full Packet (Quote + OI + Depth)
#       def self.handle_full(buf)
#         sid        = buf.unpack1('x4L<')
#         ltp        = buf.unpack1('x8e')
#         ltq        = buf.unpack1('x12S<')
#         ltt        = buf.unpack1('x14L<')
#         atp        = buf.unpack1('x18e')
#         vol        = buf.unpack1('x22L<')
#         sell_q     = buf.unpack1('x26L<')
#         buy_q      = buf.unpack1('x30L<')
#         oi         = buf.unpack1('x34L<')
#         high_oi    = buf.unpack1('x38L<')
#         low_oi     = buf.unpack1('x42L<')
#         open_v     = buf.unpack1('x46e')
#         close_v    = buf.unpack1('x50e')
#         high_v     = buf.unpack1('x54e')
#         low_v      = buf.unpack1('x58e')
#         inst = Instrument.find_by(security_id: sid) or return

#         # depth levels: 5 * 20 bytes = 100 bytes starting at byte 63
#         depth_offset = 62
#         levels = 5.times.map do |i|
#           offset = depth_offset + i*20
#           bid_qty, ask_qty, bid_odrs, ask_odrs, bid_pr, ask_pr =
#             buf.unpack1("x#{offset}l<")     ,  # bid_qty
#             buf.unpack1("x#{offset+4}l<")   ,  # ask_qty
#             buf.unpack1("x#{offset+8}S<")   ,  # bid_orders
#             buf.unpack1("x#{offset+10}S<")  ,  # ask_orders
#             buf.unpack1("x#{offset+12}e")   ,  # bid_price
#             buf.unpack1("x#{offset+16}e")      # ask_price
#           { bid_qty:, ask_qty:, bid_orders: bid_odrs,
#             ask_orders: ask_odrs, bid_price: bid_pr,
#             ask_price: ask_pr }
#         end

#         Quote.create!(
#           instrument: inst,
#           ltp:         ltp,
#           volume:      vol,
#           tick_time:   Time.at(ltt)
#         )

#         puts "[FULL] #{inst.symbol_name} LTP=#{ltp.round(2)} VOL=#{vol} DEPTH=#{levels.inspect}"
#       end

#       # 50: Disconnect notification
#       def self.handle_disconnect(buf)
#         sid         = buf.unpack1('x4L<')
#         reason_code = buf.unpack1('x8S<')
#         puts "[DISCONNECT] SID=#{sid} ReasonCode=#{reason_code}"
#       end
#     end
#   end
# end

require 'faye/websocket'
require 'eventmachine'
require 'json'
require_relative 'feed_packet'

module Dhan
  module Ws
    class FeedListener
      FEED_URL = [
        'wss://api-feed.dhan.co?version=2',
        "token=#{ENV.fetch('DHAN_ACCESS_TOKEN', nil)}",
        "clientId=#{ENV.fetch('DHAN_CLIENT_ID', nil)}",
        'authType=2'
      ].join('&').freeze

      def self.run
        EM.run do
          ws = Faye::WebSocket::Client.new(FEED_URL)
          ws.on(:open) do
            Rails.logger.debug '[WS] Connected'
            subscribe(ws)
          end
          ws.on(:message) { |e| handle(e) }
          ws.on(:close)   do
            Rails.logger.debug '[WS] Closed'
            EM.stop
            run
          end
          ws.on(:error) { |e| puts "[WS] Error: #{e.message}" }
        end
      end

      def self.subscribe(ws)
        # collect all instrument and derivative security_ids by segment
        to_subscribe = Hash.new { |h, k| h[k] = [] }

        Instrument.nse.segment_index.limit(50).find_each do |inst|
          to_subscribe[inst.exchange_segment] << inst.security_id
        end

        Derivative.nse.limit(50).find_each do |deriv|
          to_subscribe[deriv.exchange_segment] << deriv.security_id
        end

        # now send each group in slices of 100
        to_subscribe.each do |exchange_segment, ids|
          ids.uniq.each_slice(100) do |batch|
            ws.send({
              RequestCode: 15,
              InstrumentCount: batch.size,
              InstrumentList: batch.map { |sid| { ExchangeSegment: exchange_segment, SecurityId: sid } }
            }.to_json)
            Rails.logger.debug { "[WS] Subscribed #{batch.size} on #{exchange_segment}" }
          end
        end
      end

      def self.handle(event)
        data = event.data
        bytes = if data.is_a?(String)
                  # text frame or binary string
                  data.start_with?('[') ? JSON.parse(data) : data.bytes
                else
                  data
                end
        code = bytes.first
        case code
        when 2  then TickerHandler.call(bytes)
        when 4  then QuoteHandler.call(bytes)
        when 5  then OIHandler.call(bytes)
        when 6  then PrevCloseHandler.call(bytes)
        when 8  then FullHandler.call(bytes)
        else Rails.logger.debug { "[WS] Unknown code #{code}" }
        end
      rescue StandardError => e
        Rails.logger.debug { "[WS] Parse error: #{e.message}" }
      end
    end
  end
end
