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

      cache = positions.index_by do |p|
        key_for(p['securityId'], p['exchangeSegment'])
      end

      Rails.cache.write(CACHE_KEY, cache, expires_in: CACHE_TTL)
    end

    # All cached composite keys (e.g. ["12345_NSE_FNO"])
    #
    # @return [Array<String>]
    def self.keys
      Rails.cache.read(CACHE_KEY)&.keys || []
    end

    # Fetch full position for a given composite key
    #
    # @param [String, Integer] security_id
    # @param [String, Integer] exchange_segment
    # @return [Hash, nil]
    def self.fetch(security_id, exchange_segment)
      key = key_for(security_id, exchange_segment)
      Rails.cache.read(CACHE_KEY)&.[](key)
    end

    # Fetch all open positions as a hash (key => position)
    #
    # @return [Hash]
    def self.all
      Rails.cache.read(CACHE_KEY) || {}
    end

    # Fetch all positions as a list of hashes
    #
    # @return [Array<Hash>]
    def self.all_positions
      all.values
    end

    # Get composite cache key
    #
    # @param [String, Integer] security_id
    # @param [String, Integer] exchange_segment
    # @return [String]
    def self.key_for(security_id, exchange_segment)
      "#{security_id}_#{exchange_segment}"
    end
  end
end
