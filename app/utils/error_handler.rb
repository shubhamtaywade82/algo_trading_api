# frozen_string_literal: true

module ErrorHandler
  MAX_RETRIES = 0

  def self.handle_error(context:, exception:, retries: 0, retry_logic: nil)
    ErrorLogger.log_error("#{context} failed", exception)

    if retries < MAX_RETRIES && retry_logic
      Rails.logger.info("#{context} retrying... Attempt #{retries + 1}")
      retry_logic.call
    else
      Rails.logger.error("#{context} max retries exceeded. Exception: #{exception.message}")
      { error: 'An unexpected error occurred. Please try again later.' }
    end
  end
end
