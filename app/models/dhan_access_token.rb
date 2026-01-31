# frozen_string_literal: true

class DhanAccessToken < ApplicationRecord
  def self.active
    where('expires_at > ?', Time.current).order(expires_at: :desc).first
  end

  def self.valid?
    active.present?
  end
end
