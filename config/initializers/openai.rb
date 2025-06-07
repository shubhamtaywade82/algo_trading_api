# config/initializers/openai.rb
require 'openai'

OpenAI.configure do |config|
  config.access_token    = ENV.fetch('OPENAI_API_KEY') # ← keep names consistent
  config.organization_id = ENV.fetch('OPENAI_ORG_ID', nil) # optional
  config.log_errors      = !Rails.env.production?
  config.request_timeout = 90
end
