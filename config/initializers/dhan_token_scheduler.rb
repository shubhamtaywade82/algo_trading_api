# frozen_string_literal: true

# Scheduled token refresh so TokenManager.current_token! runs even when no API calls occur.
# Without this, when token expires and no jobs/requests hit Dhan, refresh never runs.
return if Rails.env.test?
return if ENV['DISABLE_TRADING_SERVICES'] == '1'
return if defined?(Rake)

Rails.application.config.after_initialize do
  next unless ActiveRecord::Base.connection.table_exists?('dhan_access_tokens')

  Thread.new do
    loop do
      Dhan::TokenManager.current_token!
      sleep 5.minutes
    rescue StandardError => e
      Rails.logger.error "[DHAN] Scheduled refresh failed: #{e.message}"
      sleep 5.minutes
    end
  end
rescue ActiveRecord::DatabaseConnectionError => e
  Rails.logger.warn "[DHAN] Token scheduler not started: #{e.message}"
end
