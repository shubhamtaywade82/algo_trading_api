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
          Rails.logger.debug { "[WS] Connecting to #{FEED_URL}" }
          ws = Faye::WebSocket::Client.new(FEED_URL)

          ws.on(:open) do
            Rails.logger.info '[WS] ▶ Connected'
            subscribe(ws)
          end

          ws.on(:message) do |event|
            handle_message(event.data)
          end

          ws.on(:close) do |event|
            Rails.logger.warn "[WS] ✖ Disconnected (#{event.code}): #{event.reason}"
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
        security_ids = Positions::ActiveCache.ids.uniq
        return if security_ids.blank?

        instrument_segments = Instrument.where(security_id: security_ids).pluck(:security_id, :exchange_segment)

        instrument_segments.group_by(&:last).each do |exchange_segment, items|
          items.map(&:first).each_slice(100) do |batch|
            ws.send({
              RequestCode: 15,
              InstrumentCount: batch.size,
              InstrumentList: batch.map { |sid| { ExchangeSegment: exchange_segment, SecurityId: sid } }
            }.to_json)
            Rails.logger.debug { "[WS] 🔔 Subscribed batch of #{batch.size} to #{exchange_segment}" }
          end
        end
      end

      def self.handle_message(data)
        return unless data.is_a?(String) && !data.start_with?('[') # ignore JSON events

        parsed = Dhanhq::WebsocketPacketParser.new(data).parse

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
                    Rails.logger.debug { "[WS] Unknown packet code: #{parsed[:feed_response_code]}" }
                    return
                  end

        handler.call(parsed) if handler.respond_to?(:call)
      rescue StandardError => e
        Rails.logger.error "[WS] ❌ Parse error: #{e.class} - #{e.message}"
      end
    end
  end
end
