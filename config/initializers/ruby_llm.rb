# frozen_string_literal: true

# RubyLLM global defaults.
#
# Only process-wide settings belong here. The Ollama API *key* deliberately
# does not: keys are rotated per request by `Llm::KeyRotator`, which builds an
# isolated `RubyLLM.context` for each attempt. Setting one globally would let a
# quarantined key leak into callers that never asked for it.
RubyLLM.configure do |config|
  # Ollama Cloud speaks the OpenAI-compatible API and RubyLLM posts to
  # `{api_base}/chat/completions`, so the base must include `/v1`.
  config.ollama_api_base = ENV['OLLAMA_API_BASE'].presence || 'https://ollama.com/v1'

  use_ollama_dev = !Rails.env.production? &&
                   (ENV['OPENAI_URI_BASE'].blank? || ENV['OPENAI_URI_BASE'].to_s.include?('11434'))

  if use_ollama_dev
    config.openai_api_base = ENV['OPENAI_URI_BASE'].presence || 'http://localhost:11434/v1'
    config.openai_api_key  = ENV['OPENAI_API_KEY'].presence || 'ollama'
  else
    config.openai_api_base = ENV['OPENAI_URI_BASE'].presence
    config.openai_api_key  = ENV.fetch('OPENAI_API_KEY', nil)
  end

  # Retries inside a single key's attempt. Rotation to the next key happens
  # above this, in Llm::KeyRotator, once these are exhausted.
  config.request_timeout = ENV.fetch('LLM_REQUEST_TIMEOUT', 120).to_i
  config.max_retries = ENV.fetch('LLM_MAX_RETRIES', 2).to_i

  config.logger = Rails.logger
  config.log_level = Rails.env.production? ? :info : :debug
  # NOTE: `use_new_acts_as` is set in config/application.rb, not here — the
  # railtie reads it before app initializers run.
end
