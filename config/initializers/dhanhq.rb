# frozen_string_literal: true

require 'dhan_hq'

DhanHQ.configure_with_env

# Prefer DHAN_CLIENT_ID; fall back to CLIENT_ID for compatibility.
client_id = ENV['DHAN_CLIENT_ID'].presence || ENV['CLIENT_ID'].presence
DhanHQ.configuration.client_id = client_id if client_id

# Inject access token from DB so the gem always uses the latest valid token.
# No refresh API exists; token must be renewed via /auth/dhan/login when expired.
DhanHQ.configuration.define_singleton_method(:access_token) do
  record = DhanAccessToken.active
  record ? record.access_token : instance_variable_get(:@access_token)
end

DhanHQ.logger.level = (ENV['DHAN_LOG_LEVEL'] || 'INFO').upcase.then { |level| Logger.const_get(level) }

# Load backwards-compatibility layer for legacy Dhanhq::API calls
# This file is excluded from Zeitwerk autoloading because it defines Dhanhq::API
# (not Dhanhq::Api as Zeitwerk expects based on the file name)
require Rails.root.join('lib/dhanhq/api').to_s
