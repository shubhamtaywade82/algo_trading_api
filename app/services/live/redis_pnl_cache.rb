# frozen_string_literal: true

module Live
  # Cross-process tick cache used for P&L marking.
  #
  # {TickCache} is per-process and feed-fed, so a web request in a process that
  # never opened the feed sees nothing. This one is backed by `Rails.cache`
  # (solid_cache here, so Postgres-backed and shared), which makes a tick
  # written by the feed daemon visible to a web or job process.
  #
  # It is intentionally the slower of the two: readers should consult
  # {TickCache} first and fall back here.
  class RedisPnlCache
    include Singleton

    NAMESPACE = 'live:tick'
    # Marking P&L against a price older than this is misleading, so entries
    # expire rather than linger.
    TTL = 60

    # @param segment [String]
    # @param security_id [String, Integer]
    # @param tick [Hash] must carry :ltp
    def store_tick(segment:, security_id:, tick:)
      Rails.cache.write(
        cache_key(segment, security_id),
        tick.to_h.symbolize_keys.merge(cached_at: Time.current),
        expires_in: TTL
      )
      tick
    rescue StandardError => e
      Rails.logger.error("[RedisPnlCache] store failed for #{segment}:#{security_id}: #{e.message}")
      nil
    end

    # @return [Hash, nil] the cached tick, falling back to the in-process cache
    def fetch_tick(segment:, security_id:)
      local = Live::TickCache.get(segment, security_id.to_s)
      return local if local

      Rails.cache.read(cache_key(segment, security_id))
    rescue StandardError => e
      Rails.logger.error("[RedisPnlCache] fetch failed for #{segment}:#{security_id}: #{e.message}")
      nil
    end

    # @return [Float, nil]
    def ltp(segment:, security_id:)
      fetch_tick(segment: segment, security_id: security_id)&.dig(:ltp)&.to_f
    end

    # Drops both caches. Called on entry so a position is never marked against
    # a price from before it existed.
    def clear_tick(segment:, security_id:)
      Live::TickCache.delete(segment, security_id.to_s)
      Rails.cache.delete(cache_key(segment, security_id))
      true
    rescue StandardError => e
      Rails.logger.error("[RedisPnlCache] clear failed for #{segment}:#{security_id}: #{e.message}")
      false
    end

    private

    def cache_key(segment, security_id)
      "#{NAMESPACE}:#{segment}:#{security_id}"
    end
  end
end
