# frozen_string_literal: true

module MarketCache
  LTP_KEY_PREFIX = 'ltp'
  META_KEY_PREFIX = 'market_data'

  def self.write_ltp(segment_key, security_id, ltp)
    key = build_key(LTP_KEY_PREFIX, segment_key, security_id)

    # Safely convert LTP to Float for caching
    numeric_ltp = ltp.respond_to?(:to_f) ? ltp.to_f : ltp
    old_ltp = Rails.cache.read(key)

    return if old_ltp == numeric_ltp

    Rails.cache.write(key, numeric_ltp, expires_in: 2.minutes)

    Rails.logger.debug { "[MarketCache] LTP updated: #{key} => #{numeric_ltp}" }
  rescue StandardError => e
    Rails.logger.error "[MarketCache] ❌ LTP write failed: #{e.class} - #{e.message}"
  end

  def self.read_ltp(segment_key, security_id)
    key = build_key(LTP_KEY_PREFIX, segment_key, security_id)
    Rails.cache.read(key)
  end

  def self.write_market_data(segment_key, security_id, data = {})
    key = build_key(META_KEY_PREFIX, segment_key, security_id)
    sanitized_data = { ltp: data[:ltp].to_f, open: data[:open].to_f, high: data[:high].to_f, low: data[:low].to_f, volume: data[:volume].to_i, oi: data[:oi].to_i, time: Time.zone.now.to_s }.compact # remove nils

    # debugger
    Rails.cache.write(key, sanitized_data, expires_in: 2.minutes)
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
