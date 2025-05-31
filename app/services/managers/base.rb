# frozen_string_literal: true

module Managers
  class Base
    def self.call(*)
      new(*).call
    end

    def log_info(message)
      Rails.logger.info(message.to_s)
    end

    def log_error(message, exception = nil)
      Rails.logger.error("#{message}: #{exception&.message}")
    end

    def execute_safely
      yield
    rescue StandardError => e
      log_error('Error during execution', e)
      raise e
    end
  end
end
