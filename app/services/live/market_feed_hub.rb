# frozen_string_literal: true

module Live
  # Singleton owning the DhanHQ market-feed WebSocket for this process.
  #
  # Wraps `DhanHQ::WS::Client` (gem >= 3.2), which handles the socket, the
  # binary decoding and reconnect-with-resubscribe. This class adds what the
  # app needs on top: a single connection per process, a subscription set that
  # survives reconnects, and ticks landing in `Live::TickCache`.
  #
  # Dhan caps a connection at 5,000 instruments and 100 per subscribe frame;
  # the SDK batches frames, and MAX_SUBSCRIPTIONS guards the former.
  #
  # Nothing here starts automatically — call `start!` from an initializer or a
  # daemon process. A web process that never starts it degrades to REST, which
  # is why every reader checks `running? && connected?` first.
  class MarketFeedHub
    include Singleton

    MAX_SUBSCRIPTIONS = 5_000
    # A feed can stay connected while the server stops publishing, so health is
    # judged on frame arrival, not socket state.
    STALE_AFTER = 45

    def initialize
      @mutex = Mutex.new
      @client = nil
      @subscriptions = Concurrent::Map.new
    end

    # Opens the feed and begins populating TickCache.
    #
    # @param mode [Symbol] :ticker, :quote or :full
    # @return [self]
    def start!(mode: :quote)
      @mutex.synchronize do
        return self if @client

        @client = build_client(mode)
        @client.start
        Rails.logger.info("[MarketFeedHub] started (mode=#{mode})")
      end
      resubscribe_all
      self
    rescue StandardError => e
      Rails.logger.error("[MarketFeedHub] start failed: #{e.class} - #{e.message}")
      @mutex.synchronize { @client = nil }
      self
    end

    def stop!
      @mutex.synchronize do
        @client&.stop
        @client = nil
      end
      Rails.logger.info('[MarketFeedHub] stopped')
      self
    end

    # @return [Boolean] whether the feed has been started in this process
    def running?
      !@client.nil?
    end

    # @return [Boolean] socket is up *and* frames are arriving
    def connected?
      client = @client
      return false unless client

      client.connected? && client.healthy?(stale_after: STALE_AFTER)
    rescue StandardError
      false
    end

    # Subscribes one instrument, remembering it so a reconnect restores it.
    #
    # @param segment [String] e.g. "NSE_FNO"
    # @param security_id [String, Integer]
    # @return [Boolean] whether the subscription was accepted
    def subscribe(segment:, security_id:)
      sid = security_id.to_s
      key = subscription_key(segment, sid)
      return true if @subscriptions.key?(key)

      if @subscriptions.size >= MAX_SUBSCRIPTIONS
        Rails.logger.warn("[MarketFeedHub] subscription cap #{MAX_SUBSCRIPTIONS} reached; refusing #{key}")
        return false
      end

      @subscriptions[key] = { segment: segment.to_s, security_id: sid }
      @client&.subscribe_one(segment: segment.to_s, security_id: sid)
      true
    rescue StandardError => e
      Rails.logger.error("[MarketFeedHub] subscribe #{segment}:#{security_id} failed: #{e.message}")
      false
    end

    def unsubscribe(segment:, security_id:)
      sid = security_id.to_s
      @subscriptions.delete(subscription_key(segment, sid))
      @client&.unsubscribe_one(segment: segment.to_s, security_id: sid)
      Live::TickCache.delete(segment, sid)
      true
    rescue StandardError => e
      Rails.logger.error("[MarketFeedHub] unsubscribe #{segment}:#{security_id} failed: #{e.message}")
      false
    end

    # @return [Array<Hash>] everything this hub believes it is subscribed to
    def subscriptions
      @subscriptions.values
    end

    # Health snapshot for a monitoring endpoint.
    # @return [Hash]
    def health
      base = { running: running?, tracked_subscriptions: @subscriptions.size, cached_ticks: Live::TickCache.size }
      client = @client
      return base.merge(connected: false) unless client

      base.merge(client.health)
    rescue StandardError => e
      base.merge(error: e.message)
    end

    private

    def build_client(mode)
      client = DhanHQ::WS::Client.new(mode: mode)

      client.on(:tick) { |tick| handle_tick(tick) }

      # 3.2 emits :reconnect with the instruments the SDK restored. Derived
      # state (candle builders, caches) can be stale across the gap, so drop
      # cached ticks rather than trade on a price from before the outage.
      client.on(:reconnect) do |info|
        Rails.logger.warn("[MarketFeedHub] reconnected (attempt=#{info[:attempt]}, " \
                          "resubscribed=#{Array(info[:resubscribed]).size})")
        Live::TickCache.clear!
        resubscribe_all
      end

      client.on(:close) { Rails.logger.warn('[MarketFeedHub] feed closed') }
      client.on(:error) { |err| Rails.logger.error("[MarketFeedHub] feed error: #{err}") }

      client
    end

    # Decoder emits { kind:, segment:, security_id:, ltp:, ... }.
    def handle_tick(tick)
      return unless tick.is_a?(Hash)

      segment = tick[:segment]
      security_id = tick[:security_id]
      return if segment.blank? || security_id.blank?

      Live::TickCache.put(segment, security_id, tick)
      drive_paper_book(segment, security_id, tick[:ltp])
    rescue StandardError => e
      Rails.logger.error("[MarketFeedHub] tick handling failed: #{e.message}")
    end

    # In paper mode the feed *is* the matching engine's clock: without this a
    # resting limit or stop would never fill, and open positions would never
    # mark. Failures are contained so a simulation bug cannot take down the
    # feed for live trading.
    def drive_paper_book(segment, security_id, ltp)
      return unless Paper::Broker.enabled?
      return if ltp.blank?

      Paper::Exchange.process_tick(security_id: security_id, exchange_segment: segment, ltp: ltp)
    rescue StandardError => e
      Rails.logger.error("[MarketFeedHub] paper tick processing failed for #{security_id}: #{e.message}")
    end

    # Replays the tracked set onto the client. The SDK resubscribes on its own
    # after a reconnect; this covers instruments subscribed while the socket
    # was down, which the SDK never saw.
    def resubscribe_all
      client = @client
      return unless client

      @subscriptions.each_value do |sub|
        client.subscribe_one(segment: sub[:segment], security_id: sub[:security_id])
      rescue StandardError => e
        Rails.logger.error("[MarketFeedHub] resubscribe #{sub[:segment]}:#{sub[:security_id]} failed: #{e.message}")
      end
    end

    def subscription_key(segment, security_id)
      "#{segment}:#{security_id}"
    end
  end
end
