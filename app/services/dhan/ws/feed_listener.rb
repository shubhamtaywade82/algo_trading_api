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

      @last_subscribed_ids = []

      def self.run
        EM.run do
          Rails.logger.debug { "[WS] Connecting to #{FEED_URL}" }
          ws = Faye::WebSocket::Client.new(FEED_URL)

          ws.on(:open) do
            Rails.logger.debug '[WS] ▶ Connected'
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
            Rails.logger.error "[WS] ⚠ Error: #{event.message}"
          end
        end
      end

      def self.subscribe(ws)
        # security_ids = Positions::ActiveCache.ids.uniq
        security_ids = [13]
        return if security_ids.blank?

        instruments = Instrument.where(security_id: security_ids)

        instrument_list = instruments.map do |instrument|
          {
            ExchangeSegment: instrument.exchange_segment,
            SecurityId: instrument.security_id.to_s
          }
        end

        payload = {
          RequestCode: 21, # Full Packet
          InstrumentCount: instrument_list.size,
          InstrumentList: instrument_list
        }

        ws.send(payload.to_json)
      end

      def self.handle_message(data)
        return unless data.is_a?(String) && !data.start_with?('[')

        packet = WebsocketPacketParser.new(data).parse
        return if packet.blank?

        case packet[:feed_response_code]
        when 8
          FullHandler.call(packet)
        when 50
          Rails.logger.warn "[WS] ✖ Disconnection notice for SID=#{packet[:security_id]}, Code=#{packet[:disconnection_code]}"
        else
          Rails.logger.debug { "[WS] Ignored packet type: #{packet[:feed_response_code]}" }
        end
      rescue StandardError => e
        Rails.logger.error "[WS] ❌ Parse/Dispatch Error: #{e.class} - #{e.message}"
      end
    end
  end
end