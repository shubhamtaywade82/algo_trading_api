# frozen_string_literal: true

require 'dhanhq'

Dhanhq.configure do |config|
  config.client_id = ENV.fetch('DHAN_CLIENT_ID', nil)
  config.access_token = ENV.fetch('DHAN_ACCESS_TOKEN', nil)
end
