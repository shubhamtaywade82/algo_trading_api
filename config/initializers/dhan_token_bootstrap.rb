Rails.application.config.after_initialize do
  next if Rails.env.test?
  next if ENV['DISABLE_TRADING_SERVICES'] == '1'
  next if defined?(Rake) # skip during db:migrate and other rake tasks

  Dhan::TokenManager.current_token!
rescue StandardError => e
  Rails.logger.warn "[DHAN] Token bootstrap skipped: #{e.class} - #{e.message}"
end
