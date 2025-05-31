# frozen_string_literal: true

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

      @last_subscribed_ids = []

      def self.run
        EM.run do
          puts "[WS] Connecting to #{FEED_URL}"
          ws = Faye::WebSocket::Client.new(FEED_URL)

          ws.on(:open) do
            puts '[WS] ▶ Connected'
            subscribe(ws)
          end

          ws.on(:message) do |event|
            handle_message(event.data)
          end

          ws.on(:close) do |event|
            puts "[WS] ✖ Disconnected (#{event.code}): #{event.reason}"
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

        pp payload
        ws.send(payload.to_json)
      end

      def self.handle_message(data)
        return unless data.is_a?(String) && !data.start_with?('[') # ignore JSON events

        parsed = Dhan::Ws::WebsocketPacketParser.new(data).parse

        handler = case parsed[:feed_response_code]
                  when 2  then TickerHandler
                  when 4  then QuoteHandler
                  when 5  then OIHandler
                  when 6  then PrevCloseHandler
                  when 8  then FullHandler
                  when 50 then lambda { |p|
                    Rails.logger.warn "[WS] Disconnected: SID=#{p[:security_id]}, Code=#{p[:disconnection_code]}"
                  }
                  else
                    puts { "[WS] Unknown packet code: #{parsed[:feed_response_code]}" }
                    return
                  end

        handler.call(parsed) if handler.respond_to?(:call)
      rescue StandardError => e
        Rails.logger.error "[WS] ❌ Parse error: #{e.class} - #{e.message}"
      end
    end
  end
end
