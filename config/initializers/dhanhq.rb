# frozen_string_literal: true

require 'dhanhq'

Dhanhq.configure do |config|
  config.client_id = ENV.fetch('DHAN_CLIENT_ID', nil)
  config.access_token = ENV.fetch('DHAN_ACCESS_TOKEN', nil)

  # Optional explicit sandbox for safety:
  config.base_url = if Rails.env.test?
                      Dhanhq::Constants::LIVE_BASE_URL
                    else
                      Dhanhq::Constants::LIVE_BASE_URL
                    end
end
