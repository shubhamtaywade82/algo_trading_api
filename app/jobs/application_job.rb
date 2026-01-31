# frozen_string_literal: true

class ApplicationJob < ActiveJob::Base
  before_perform :ensure_dhan_token!

  discard_on Exceptions::DhanTokenExpiredError # No retries; re-login and next schedule will run

  retry_on StandardError, attempts: 5, wait: :exponentially_longer

  rescue_from(StandardError) do |exception|
    ErrorLogger.log_error('Job failed', exception) unless exception.is_a?(Exceptions::DhanTokenExpiredError)
    raise exception
  end

  private

  def ensure_dhan_token!
    return if DhanAccessToken.valid?

    raise Exceptions::DhanTokenExpiredError
  end
end
