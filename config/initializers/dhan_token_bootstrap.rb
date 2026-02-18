Rails.application.config.after_initialize do
  next if Rails.env.test?
  next if ENV['DISABLE_TRADING_SERVICES'] == '1'

  Dhan::TokenManager.current_token!
end
