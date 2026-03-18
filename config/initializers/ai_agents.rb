# frozen_string_literal: true

require 'agents'

# ai-agents gem configuration (https://github.com/chatwoot/ai-agents)
#
# Provider selection:
# - OpenAI (cloud): set OPENAI_API_KEY; leave OPENAI_URI_BASE unset or set to https://api.openai.com/v1
# - Ollama (local):  set OPENAI_URI_BASE=http://localhost:11434/v1 and optionally OPENAI_OLLAMA_MODEL=qwen3:latest
Agents.configure do |config|
  config.openai_api_key  = ENV['OPENAI_API_KEY']
  config.anthropic_api_key = ENV['ANTHROPIC_API_KEY'] if ENV['ANTHROPIC_API_KEY'].present?

  use_ollama = ENV['OPENAI_URI_BASE'].to_s.include?('11434')
  if use_ollama
    config.openai_api_base = ENV['OPENAI_URI_BASE'].presence || 'http://localhost:11434/v1'
    config.default_model   = ENV.fetch('OPENAI_OLLAMA_MODEL', 'qwen3:latest')
  else
    config.default_model = Rails.env.production? ? 'gpt-4o-mini' : 'gpt-4o'
  end

  config.debug = Rails.env.development?
end
