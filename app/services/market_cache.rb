# frozen_string_literal: true

module MarketCache
  LTP_KEY_PREFIX = 'ltp'
  META_KEY_PREFIX = 'market_data'

  def self.write_ltp(segment_key, security_id, ltp)
    key = build_key(LTP_KEY_PREFIX, segment_key, security_id)
    old_ltp = Rails.cache.read(key)
    return if old_ltp == ltp

    Rails.cache.write(key, ltp, expires_in: 2.minutes)
    Rails.logger.debug { "[MarketCache] LTP updated: #{key} => #{ltp}" }
  rescue StandardError => e
    Rails.logger.error "[MarketCache] ❌ LTP write failed: #{e.class} - #{e.message}"
  end

  def self.read_ltp(segment_key, security_id)
    key = build_key(LTP_KEY_PREFIX, segment_key, security_id)
    Rails.cache.read(key)
  end

  # Write full market data as a structured hash
  def self.write_market_data(segment_key, security_id, data = {})
    key = build_key(META_KEY_PREFIX, segment_key, security_id)
    Rails.cache.write(key, data, expires_in: 2.minutes)
    Rails.logger.debug { "[MarketCache] Market data written for #{key}" }
  rescue StandardError => e
    Rails.logger.error "[MarketCache] ❌ Market data write failed: #{e.class} - #{e.message}"
  end

  def self.read_market_data(segment_key, security_id)
    key = build_key(META_KEY_PREFIX, segment_key, security_id)
    Rails.cache.read(key)
  end

  def self.build_key(type_prefix, segment_key, security_id)
    "#{type_prefix}_#{segment_key}_#{security_id}"
  end
end
