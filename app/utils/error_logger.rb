# frozen_string_literal: true

module ErrorLogger
  # Frames of backtrace kept. A job that is logged here rather than re-raised
  # never prints a stack trace of its own, and the message alone does not
  # locate a NoMethodError; the full trace is sixty frames of framework.
  BACKTRACE_FRAMES = 5

  def self.log_error(message, exception = nil)
    Rails.logger.error("#{message}: #{exception&.message}")
    # Integrate with external monitoring tools like Sentry or Rollbar here
    return if exception&.backtrace.blank?

    Rails.logger.error(exception.backtrace.first(BACKTRACE_FRAMES).map { |line| "  #{line}" }.join("\n"))
  end
end
