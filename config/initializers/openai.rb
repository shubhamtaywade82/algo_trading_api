# config/initializers/openai.rb
# In development: uses local Ollama (http://localhost:11434/v1) by default.
# Set OPENAI_URI_BASE to e.g. https://api.openai.com/v1 to use OpenAI in dev.
# Set OPENAI_OLLAMA_MODEL (app-scoped) or OLLAMA_MODEL for the model (default: llama3.1:8b-instruct-q4_K_M).
# OPENAI_OLLAMA_MODEL wins so .env overrides a global OLLAMA_MODEL (e.g. from Cursor/shell).
require 'openai'

use_ollama = !Rails.env.production? &&
             (ENV['OPENAI_URI_BASE'].blank? || ENV['OPENAI_URI_BASE'].to_s.include?('11434'))

OpenAI.configure do |config|
  if use_ollama
    config.uri_base       = ENV['OPENAI_URI_BASE'].presence || 'http://localhost:11434/v1'
    config.access_token   = ENV['OPENAI_API_KEY'].presence || 'ollama'
    config.organization_id = nil
  else
    config.access_token = ENV.fetch('OPENAI_API_KEY')
    config.organization_id = ENV.fetch('OPENAI_ORG_ID', nil)
  end
  config.log_errors      = !Rails.env.production?
  config.request_timeout = 360
end
