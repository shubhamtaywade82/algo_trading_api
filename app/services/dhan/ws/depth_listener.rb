# frozen_string_literal: true

require 'faye/websocket'
require 'eventmachine'
require 'json'
require_relative 'depth_packet'

module Dhan
  module Ws
    class DepthListener
      DEPTH_BASE = 'wss://depth-api-feed.dhan.co/twentydepth?'

      def self.depth_url
        [DEPTH_BASE, "token=#{ws_token}", "clientId=#{ws_client_id}", 'authType=2'].join('&')
      end

      def self.ws_token
        DhanAccessToken.active&.access_token || ENV.fetch('ACCESS_TOKEN', nil)
      end

      def self.ws_client_id
        ENV['DHAN_CLIENT_ID'].presence || ENV['CLIENT_ID'].presence
      end

      def self.run
        EM.run do
          url = depth_url
          Rails.logger.debug { "[Depth] Connecting to #{url}" }
          ws = Faye::WebSocket::Client.new(url)

          ws.on(:open) do
            Rails.logger.debug '[Depth] ▶ Connected'
            subscribe(ws)
          end
          ws.on(:message) { |e| handle_frame(e.data) }
          ws.on(:close)   do |e|
            Rails.logger.debug { "[Depth] ✖ Closed (#{e.code})" }
            EM.stop
            run
          end
          ws.on(:error) { |e| puts "[Depth] ⚠ Error: #{e.message}" }
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
              RequestCode: 23,
              InstrumentCount: batch.size,
              InstrumentList: batch.map { |sid| { ExchangeSegment: exchange_segment, SecurityId: sid } }
            }.to_json)
            Rails.logger.debug { "[WS] Subscribed #{batch.size} on #{exchange_segment}" }
          end
        end
      end

      def self.handle_frame(data)
        Rails.logger.debug data
        bytes  = data.is_a?(String) ? data.bytes : Array(data)
        header = bytes[2] # feed code lives in the 3rd byte of depth header
        return unless [41, 51].include?(header)

        # strip the 12-byte header, parse the 20 levels
        levels = DepthPacket.parse(bytes)
        # you might persist into a `DepthQuote` model:
        # DepthQuote.create!(exchange_segment:…, security_id:…, levels: levels)

        Rails.logger.debug { "[Depth] Parsed #{levels.size == 2 ? 'Bid+Ask' : ''} levels" }
      rescue StandardError => e
        Rails.logger.debug { "[Depth] Parse error: #{e.class}: #{e.message}" }
      end
    end
  end
end
