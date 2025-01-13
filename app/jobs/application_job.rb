# frozen_string_literal: true

class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  retry_on StandardError, attempts: 5, wait: :exponentially_longer

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError

  rescue_from(StandardError) do |exception|
    ErrorLogger.log_error('Job failed', exception)
    raise exception
  end
end
