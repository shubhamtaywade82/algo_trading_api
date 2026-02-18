# frozen_string_literal: true

require 'DhanHQ/errors'
require 'dhan_hq'

# ------------------------------------------------------------
# Base Configuration
# ------------------------------------------------------------

DhanHQ.configure_with_env

# Prefer DHAN_CLIENT_ID; fall back to CLIENT_ID for compatibility
client_id = ENV['DHAN_CLIENT_ID'].presence || ENV['CLIENT_ID'].presence
DhanHQ.configuration.client_id = client_id if client_id

# ------------------------------------------------------------
# Dynamic Access Token (TOTP + TokenManager)
# ------------------------------------------------------------

DhanHQ.configure do |config|
  config.access_token_provider = lambda do
    Dhan::TokenManager.current_token!
  end

  config.on_token_expired = lambda do |error|
    Rails.logger.warn "[DHAN] Token expired detected: #{error.class}"
    Dhan::TokenManager.refresh!
  end
end

# ------------------------------------------------------------
# Logger Configuration
# ------------------------------------------------------------

log_level = (ENV['DHAN_LOG_LEVEL'] || 'INFO').upcase
DhanHQ.logger.level =
  Logger.const_defined?(log_level) ? Logger.const_get(log_level) : Logger::INFO

# ------------------------------------------------------------
# Backwards Compatibility Layer
# ------------------------------------------------------------

# This file is excluded from Zeitwerk autoloading because it defines
# Dhanhq::API (not Dhanhq::Api as Zeitwerk expects)
require Rails.root.join('lib/dhanhq/api').to_s
