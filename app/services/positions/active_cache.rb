# frozen_string_literal: true

# Caches open DhanHQ positions for ultra-fast lookup and polling avoidance.
module Positions
  class ActiveCache
    CACHE_KEY = 'active_positions_cache'
    CACHE_TTL = 60 # seconds

    # Refreshes cache from DhanHQ API (run every 30-60s)
    # @return [void]
    def self.refresh!
      positions = Dhanhq::API::Portfolio.positions.reject { |p| p['netQty'].to_f.zero? }
      cache = positions.index_by { |p| p['securityId'].to_s }
      Rails.cache.write(CACHE_KEY, cache, expires_in: CACHE_TTL)
    end

    # All cached security ids
    # @return [Array<String>]
    def self.ids
      Rails.cache.read(CACHE_KEY)&.keys || []
    end

    # Full hash for a securityId
    # @param [String, Integer] security_id
    # @return [Hash, nil]
    def self.fetch(security_id)
      Rails.cache.read(CACHE_KEY)&.[](security_id.to_s)
    end

    # All open positions hash (security_id => pos_hash)
    # @return [Hash]
    def self.all
      Rails.cache.read(CACHE_KEY) || {}
    end
  end
end
