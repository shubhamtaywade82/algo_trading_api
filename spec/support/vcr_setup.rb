# frozen_string_literal: true

require 'vcr'
require 'webmock/rspec'

VCR.configure do |config|
  config.cassette_library_dir = 'spec/vcr_cassettes'
  config.hook_into :webmock
  config.configure_rspec_metadata!
  config.allow_http_connections_when_no_cassette = true

  # Filter sensitive data from cassettes
  config.filter_sensitive_data('<ACCESS_TOKEN>') { ENV.fetch('DHAN_ACCESS_TOKEN', nil) }
  config.filter_sensitive_data('<CLIENT_ID>') { ENV.fetch('DHAN_CLIENT_ID', nil) }
  config.filter_sensitive_data('<CLIENT_ID>') { ENV.fetch('CLIENT_ID', nil) }
end
