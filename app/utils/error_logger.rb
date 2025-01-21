# frozen_string_literal: true

module ErrorLogger
  def self.log_error(message, exception = nil)
    Rails.logger.error("#{message}: #{exception&.message}")
    # Integrate with external monitoring tools like Sentry or Rollbar here
  end
end
