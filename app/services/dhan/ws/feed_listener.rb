# frozen_string_literal: true

require 'faye/websocket'
require 'eventmachine'
require 'json'

module Dhan
  module Ws
    class FeedListener
      FEED_URL = [
        'wss://api-feed.dhan.co?version=2',
        "token=#{ENV.fetch('DHAN_ACCESS_TOKEN', nil)}",
        "clientId=#{ENV.fetch('DHAN_CLIENT_ID', nil)}",
        'authType=2'
      ].join('&').freeze

      @last_subscribed_keys = Set.new

      # Always subscribe to NIFTY + BANKNIFTY
      INDEXES = [
        { security_id: '13', exchange_segment: 'IDX_I' },
        { security_id: '25', exchange_segment: 'IDX_I' }
      ].freeze

      def self.run
        Positions::ActiveCache.refresh!
        EM.run do
          pp { "[WS] Connecting to #{FEED_URL}" }
          ws = Faye::WebSocket::Client.new(FEED_URL)

          ws.on(:open) do
            pp '[WS] ▶ Connected'
            subscribe(ws)
          end

          ws.on(:message) do |event|
            handle_message(event.data)
          end

          ws.on(:close) do |event|
            Rails.logger.warn { "[WS] ✖ Disconnected (#{event.code}): #{event.reason}" }
            EM.stop
            sleep 1
            run
          end
          ws.on(:error) do |event|
            pp "[WS] ⚠ Error: #{event.message}"
          end
        end
      end

      def self.subscribe(ws)
        active_keys = Set.new

        # Add index keys
        INDEXES.each do |ix|
          active_keys << "#{ix[:security_id]}_#{reverse_convert_segment(ix[:exchange_segment])}"
        end

        # Add active positions
        Positions::ActiveCache.all.each do |sid, pos|
          seg_key = pos['exchangeSegment']
          seg_enum = reverse_convert_segment(seg_key)
          next unless seg_enum

          active_keys << sid
        end

        pp active_keys
        return if active_keys == @last_subscribed_keys

        # Convert keys to payload format
        instruments = active_keys.map do |key|
          sid, seg_enum = key.split('_')

          {
            ExchangeSegment: reverse_convert_segment(seg_enum.to_i),
            SecurityId: sid.to_s
          }
        end

        payload = {
          RequestCode: 21,
          InstrumentCount: instruments.size,
          InstrumentList: instruments
        }

        pp payload
        @last_subscribed_keys = active_keys

        pp "[WS] 📡 Subscribed to #{instruments.size} instruments: #{active_keys.to_a.join(', ')}"
        ws.send(payload.to_json)
      end

      def self.handle_message(data)
        pp data
        return unless data.is_a?(String) && !data.start_with?('[')

        packet = WebsocketPacketParser.new(data).parse
        return if packet.blank?

        pp packet
        case packet[:feed_response_code]
        when 8
          FullHandler.call(packet)
        when 50
          Rails.logger.warn "[WS] ✖ Disconnection for SID=#{packet[:security_id]} Code=#{packet[:disconnection_code]}"
        else
          pp { "[WS] Ignored packet type: #{packet[:feed_response_code]}" }
        end
      rescue StandardError => e
        Rails.logger.error "[WS] ❌ Parse/Dispatch Error: #{e.class} - #{e.message}"
      end

      # Ensures exchange_segment is always the string key (e.g., "NSE_FNO")
      #
      # @param [String, Integer] segment
      # @return [String]
      def self.reverse_convert_segment(segment)
        if segment.is_a?(Integer)
          DhanhqMappings::SEGMENT_ENUM_TO_KEY[segment] || segment.to_s
        else
          DhanhqMappings::SEGMENT_KEY_TO_ENUM[segment]
        end
      end
    end
  end
end
