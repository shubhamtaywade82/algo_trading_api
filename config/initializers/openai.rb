# # config/initializers/openai.rb
# OPENAI_SDK = ENV.fetch('OPENAI_SDK', 'official')

# case OPENAI_SDK
# when 'official'
#   require 'openai'       # official gem
# when 'community'
#   require 'ruby-openai'  # ruby-openai gem (v8.2+)
#   OpenAI.configure do |config|
#     config.access_token = ENV.fetch('OPENAI_API_KEY') # ← keep names consistent
#     config.organization_id = ENV.fetch('OPENAI_ORG_ID', nil) # optional
#     config.log_errors      = !Rails.env.production?
#     config.request_timeout = 90
#   end
# else
#   raise "Unknown OPENAI_SDK=#{OPENAI_SDK.inspect} (expected 'official' or 'community')"
# end

# frozen_string_literal: true

# Keep only simple defaults & knobs here – NO gem requires or config.
ENV['OPENAI_LIGHT_MODEL'] ||= 'gpt-4o-mini'
ENV['OPENAI_HEAVY_MODEL'] ||= 'gpt-5'      # use only if you have access
ENV['OPENAI_TOKEN_SWITCH'] ||= '200'       # rough token switch threshold

# Optional: default temp/timeout/etc — used by your own code, not the gems.
ENV['OPENAI_DEFAULT_TEMPERATURE'] ||= '0.4'