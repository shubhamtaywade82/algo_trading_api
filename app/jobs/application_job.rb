# frozen_string_literal: true

class ApplicationJob < ActiveJob::Base
  before_perform :ensure_dhan_token!

  retry_on StandardError, attempts: 5, wait: :exponentially_longer

  rescue_from(StandardError) do |exception|
    ErrorLogger.log_error('Job failed', exception)
    raise exception
  end

  private

  def ensure_dhan_token!
    Dhan::TokenManager.current_token!
  rescue StandardError => e
    Rails.logger.error("[DHAN] Token ensure failed: #{e.class} - #{e.message}")
    raise
  end
end