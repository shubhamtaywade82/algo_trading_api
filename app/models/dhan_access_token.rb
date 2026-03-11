# frozen_string_literal: true

# Stores Dhan API access token and expiry; used by TokenManager and legacy .active/.valid?.
# When multiple rows exist, only the most recently created is valid (Dhan invalidates prior tokens).
class DhanAccessToken < ApplicationRecord
  CACHE_KEY = 'dhan_access_token/active'
  CACHE_TTL = 30.seconds

  scope :non_expired, -> { where('expires_at > ?', Time.current) }
  scope :newest_first, -> { order(created_at: :desc) }

  class << self
    # Returns the single valid token: most recently created and not yet expired.
    def active
      Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) do
        current_record
      end
    end

    # Uncached; use when you need fresh DB state (e.g. inside TokenManager lock).
    def current_record
      non_expired.newest_first.first
    end

    def valid?
      active.present?
    end

    def clear_active_cache
      Rails.cache.delete(CACHE_KEY)
    end
  end

  after_create :clear_active_cache

  private

  def clear_active_cache
    self.class.clear_active_cache
  end
end
