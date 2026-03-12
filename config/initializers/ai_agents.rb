# frozen_string_literal: true

# ai-agents gem configuration (https://github.com/chatwoot/ai-agents)
#
# The gem is provider-agnostic. We point it at OpenAI by default;
# set OPENAI_URI_BASE to an Ollama endpoint for local inference.
Agents.configure do |config|
  config.openai_api_key  = ENV['OPENAI_API_KEY']
  config.anthropic_api_key = ENV['ANTHROPIC_API_KEY'] if ENV['ANTHROPIC_API_KEY'].present?

  config.default_provider = :openai

  # Use Ollama locally when OPENAI_URI_BASE points to a local server
  if ENV['OPENAI_URI_BASE'].present? && ENV['OPENAI_URI_BASE'].include?('11434')
    config.default_model = ENV.fetch('OPENAI_OLLAMA_MODEL', 'qwen3:latest')
  else
    config.default_model = Rails.env.production? ? 'gpt-4o-mini' : 'gpt-4o'
  end

  config.max_turns     = 10
  config.debug         = Rails.env.development?
end
