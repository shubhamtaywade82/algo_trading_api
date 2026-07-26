# frozen_string_literal: true

module Live
  # Process-local store of the most recent tick per instrument.
  #
  # The market feed pushes several hundred ticks a second, so this is
  # deliberately in-memory rather than Redis-backed: a read has to be cheap
  # enough that `Instrument#ltp` can consult it on every call. `RedisPnlCache`
  # covers the cross-process case.
  #
  # Keys are `"SEGMENT:security_id"`; both parts are normalised to strings so a
  # caller passing an Integer security id hits the same entry as one passing a
  # String.
  module TickCache
    # A tick older than this is treated as absent — a stale price is worse than
    # no price, since the caller then falls back to REST.
    DEFAULT_TTL = 30

    class << self
      # Stores a decoded tick.
      #
      # @param segment [String] e.g. "NSE_FNO"
      # @param security_id [String, Integer]
      # @param tick [Hash] decoded payload; :ltp is the only required key
      # @return [Hash] the stored tick
      def put(segment, security_id, tick)
        store[key(segment, security_id)] = tick.to_h.symbolize_keys.merge(cached_at: Time.current)
      end
      alias write put

      # @return [Hash, nil] the last tick, or nil when absent or stale
      def get(segment, security_id, ttl: DEFAULT_TTL)
        tick = store[key(segment, security_id)]
        return nil unless tick

        fresh?(tick, ttl) ? tick : nil
      end

      # @return [Float, nil] last traded price, or nil when absent or stale
      def ltp(segment, security_id, ttl: DEFAULT_TTL)
        tick = get(segment, security_id, ttl: ttl)
        return nil unless tick

        price = tick[:ltp]
        price&.to_f
      end

      # @return [Integer] number of cached instruments
      delegate :size, to: :store

      def delete(segment, security_id)
        store.delete(key(segment, security_id))
      end

      def clear!
        store.clear
      end

      # @return [Hash] every fresh tick, keyed by "SEGMENT:security_id"
      def snapshot(ttl: DEFAULT_TTL)
        store.each_pair.with_object({}) do |(k, tick), out|
          out[k] = tick if fresh?(tick, ttl)
        end
      end

      private

      # Concurrent::Map so feed threads writing and request threads reading do
      # not need an explicit lock.
      def store
        @store ||= Concurrent::Map.new
      end

      def key(segment, security_id)
        "#{segment}:#{security_id}"
      end

      def fresh?(tick, ttl)
        cached_at = tick[:cached_at]
        return true if cached_at.nil? || ttl.nil?

        cached_at > ttl.seconds.ago
      end
    end
  end
end
