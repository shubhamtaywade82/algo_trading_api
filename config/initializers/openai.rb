# config/initializers/openai.rb
#
# OpenAI is the default provider. Local/dev can use Ollama:
#   LLM_PROVIDER=ollama
#   OLLAMA_MODEL=llama3.1:8b  # optional; default is llama3.1:8b
#
# In that case we must not require/configure OpenAI at boot.

provider = ENV.fetch('LLM_PROVIDER', 'openai').to_s.downcase
return if provider == 'ollama'

# In test/dev, avoid hard-failing boot when OPENAI_API_KEY isn't configured.
api_key =
  if Rails.env.production?
    ENV.fetch('OPENAI_API_KEY')
  else
    ENV.fetch('OPENAI_API_KEY', nil)
  end

return if api_key.blank?

require 'openai'

OpenAI.configure do |config|
  config.access_token = api_key
  config.organization_id = ENV.fetch('OPENAI_ORG_ID', nil) # optional
  config.log_errors = !Rails.env.production?
  config.request_timeout = 360
end
