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
      @instrument_cache ||= {}
      @segment_cache ||= {}
      @ltp_cache ||= {}

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
        index_keys = Set.new
        full_keys = Set.new

        # Add static indexes (NIFTY, BANKNIFTY)
        # INDEXES.each do |ix|
        #   index_keys << "#{ix[:security_id]}_#{reverse_convert_segment(ix[:exchange_segment])}"
        # end

        # Add tradable active positions
        Positions::ActiveCache.all.each do |sid, pos|
          seg_key = pos['exchangeSegment']
          next unless seg_key.present?

          # Assume tradable if FullPacket supported
          full_keys << "#{sid}_#{seg_key}"
        end

        combined_keys = index_keys + full_keys
        return if combined_keys == @last_subscribed_keys

        @last_subscribed_keys = combined_keys

        # Build and send Quote Packet (RequestCode 17) for index instruments
        send_subscriptions(ws, index_keys, 17)

        # Build and send Full Packet (RequestCode 21) for tradable instruments
        send_subscriptions(ws, full_keys, 21)
      end

      def self.send_subscriptions(ws, key_set, request_code)
        return if key_set.empty?

        instruments = key_set.map do |key|
          sid, seg_enum = key.split('_')
          {
            ExchangeSegment: reverse_convert_segment(seg_enum.to_i),
            SecurityId: sid.to_s
          }
        end

        instruments.each_slice(100) do |batch|
          payload = {
            RequestCode: request_code,
            InstrumentCount: batch.size,
            InstrumentList: batch
          }

          ws.send(payload.to_json)
          pp "[WS] 📡 Subscribed #{batch.size} instruments via code #{request_code}: #{batch.map { |i| i[:SecurityId] }.join(', ')}"
        end
      end

      def self.handle_message(data)
        return unless data.is_a?(String) && !data.start_with?('[')

        packet = WebsocketPacketParser.new(data).parse
        return if packet.blank?

        log_ltp_change(packet)
        case packet[:feed_response_code]
        when 8
          FullHandler.call(packet)
        when 4
          QuoteHandler.call(packet)
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
        @segment_cache[segment] ||= if segment.is_a?(Integer)
                                      DhanhqMappings::SEGMENT_ENUM_TO_KEY[segment] || segment.to_s
                                    else
                                      DhanhqMappings::SEGMENT_KEY_TO_ENUM[segment]
                                    end
      end

      def self.find_instrument_cached(security_id, segment_enum)
        segment_key = reverse_convert_segment(segment_enum.to_i)
        cache_key = "#{segment_key}_#{security_id}"

        @instrument_cache ||= {}
        return @instrument_cache[cache_key] if @instrument_cache.key?(cache_key)
        return if segment_key == 'MCX_COMM'

        instrument = case segment_key
                     when 'IDX_I'     then Instrument.segment_index.find_by(security_id: security_id.to_i)
                     when 'NSE_EQ'    then Instrument.segment_equity.find_by(security_id: security_id)
                     when 'NSE_FNO'   then Instrument.segment_fno.find_by(security_id: security_id)
                     when 'MCX_COMM'  then Instrument.segment_commodity.find_by(security_id: security_id)
                     else
                       Instrument.find_by(security_id: security_id) # fallback if unknown
                     end
        @instrument_cache[cache_key] = instrument
      end

      def self.log_ltp_change(packet)
        return unless packet[:ltp]

        segment_key = reverse_convert_segment(packet[:exchange_segment])
        sid = packet[:security_id]
        key = "#{segment_key}_#{sid}"
        new_ltp = packet[:ltp].round(2)

        prev_ltp = @ltp_cache[key]
        return if prev_ltp.to_i == new_ltp.to_i

        @ltp_cache[key] = new_ltp

        instrument = find_instrument_cached(sid, packet[:exchange_segment])
        name = instrument&.symbol_name || key

        pp "[WS] 🔄 #{name} LTP changed: #{prev_ltp} → #{new_ltp}"
      end
    end
  end
end
