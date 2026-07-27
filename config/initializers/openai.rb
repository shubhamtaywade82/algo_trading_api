# config/initializers/openai.rb
# In development: uses local Ollama (http://localhost:11434/v1) by default.
# Set OPENAI_URI_BASE to e.g. https://api.openai.com/v1 to use OpenAI in dev.
# Set OPENAI_OLLAMA_MODEL (app-scoped) or OLLAMA_MODEL for the model (default: qwen3:latest).
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
    # Deliberately not ENV.fetch without a default: that raised KeyError during
    # initialization and took the whole production boot down before the app
    # served a request — including deploys that never intended to use OpenAI,
    # such as LLM_BACKEND=ollama_cloud. A missing key should fail on the call
    # that needs it, not at boot.
    config.access_token = ENV['OPENAI_API_KEY'].to_s
    config.organization_id = ENV.fetch('OPENAI_ORG_ID', nil)

    if ENV['OPENAI_API_KEY'].blank? && !ENV['LLM_BACKEND'].to_s.casecmp('ollama_cloud').zero?
      Rails.logger.warn('[Openai] OPENAI_API_KEY is not set; OpenAI-backed chat calls will fail when made.')
    end
  end
  config.log_errors      = !Rails.env.production?
  config.request_timeout = 360
end
