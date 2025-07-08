# frozen_string_literal: true

require 'vcr'
require 'webmock/rspec'

VCR.configure do |config|
  config.cassette_library_dir = 'spec/vcr_cassettes'
  config.hook_into :webmock
  config.configure_rspec_metadata!
  config.allow_http_connections_when_no_cassette = false # <--- Forces all HTTP to be stubbed/cassetted
  config.default_cassette_options = { record: :once }

  # You can filter sensitive data, e.g. API keys:
  config.filter_sensitive_data('<ACCESS_TOKEN>') { ENV.fetch('DHAN_CLIENT_ID', nil) }
  config.filter_sensitive_data('<CLIENT_ID>') { ENV.fetch('DHAN_ACCESS_TOKEN', nil) }

  # Optionally, allow localhost connections for Selenium, etc.
  config.ignore_localhost = true
end

# Also, generally enable WebMock for all tests
WebMock.disable_net_connect!(allow_localhost: true)
