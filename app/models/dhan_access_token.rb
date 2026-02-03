# frozen_string_literal: true

class DhanAccessToken < ApplicationRecord
  CACHE_KEY = 'dhan_access_token/active'
  CACHE_TTL = 30.seconds

  class << self
    def active
      Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) do
        where('expires_at > ?', Time.current).order(expires_at: :desc).first
      end
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
