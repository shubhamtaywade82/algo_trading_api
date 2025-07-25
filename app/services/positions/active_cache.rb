# frozen_string_literal: true

# Caches open DhanHQ positions for ultra-fast lookup and polling avoidance.
module Positions
  class ActiveCache
    CACHE_KEY = 'active_positions_cache'
    CACHE_TTL = 30 # seconds
    REFRESH_SEC = 30

    # Refreshes cache from DhanHQ API (run every 30-60s)
    #
    # @return [void]
    def self.refresh!
      positions = Dhanhq::API::Portfolio.positions.reject { |p| p['netQty'].to_f.zero? }

      # Normalize exchange segment as string key
      normalized = positions.index_by do |p|
        security_id = p['securityId']
        exchange_segment = reverse_convert_segment(p['exchangeSegment'])

        key_for(security_id, exchange_segment)
      end

      Rails.cache.write(CACHE_KEY, normalized, expires_in: CACHE_TTL)
    end

    # All cached composite keys (e.g. ["1333_NSE_FNO"])
    #
    # @return [Array<String>]
    def self.keys
      all.keys
    end

    # Return all cached security IDs
    #
    # @return [Array<String>]
    def self.ids
      all.keys.map { |k| k.split('_').first }
    end

    # Fetch full position for a given composite key
    #
    # @param [String, Integer] security_id
    # @param [String] exchange_segment
    # @return [Hash, nil]
    def self.fetch(security_id, exchange_segment)
      key = key_for(security_id, reverse_convert_segment(exchange_segment))
      all[key]
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

    # Generate a consistent cache key
    #
    # @param [String, Integer] security_id
    # @param [String] exchange_segment
    # @return [String]
    def self.key_for(security_id, exchange_segment_enum)
      "#{security_id}_#{exchange_segment_enum}"
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
