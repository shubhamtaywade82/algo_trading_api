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
    Rails.logger.warn "[DHAN] Hard auth failure detected: #{error.class}"
    Dhan::TokenManager.force_refresh!
  end

  # ----------------------------------------------------------
  # Write safety (DhanHQ >= 3.2)
  # ----------------------------------------------------------

  # The SDK stopped auto-retrying order placement/modify/cancel because the
  # Dhan API has no idempotency key: a timed-out POST /v2/orders may already
  # have reached the exchange, so a retry can place a second real order.
  # Leave this off and reconcile instead — Orders::Gateway returns
  # `reconcilable: true` on transient write failures. Reads keep their backoff.
  config.retry_non_idempotent_writes = ENV['DHAN_RETRY_WRITES'] == 'true'

  # Stamp a correlationId on placements that lack one so a timed-out order can
  # be resolved via GET /v2/orders/external/{correlation-id}. Defaults on here
  # because it is what makes the reconciliation path above actually usable.
  config.auto_correlation_id = ENV.fetch('DHAN_AUTO_CORRELATION_ID', 'true') == 'true'

  # SDK-level dry run: suppresses every state-changing request and answers
  # placements with a simulated DRYRUN-... id, while reads still hit the live
  # API. This is a rehearsal mode, distinct from the app's PLACE_ORDER gate —
  # PLACE_ORDER short-circuits before the SDK is called at all.
  config.dry_run = ENV['DHAN_DRY_RUN'] == 'true'
end

Rails.logger.warn '[DHAN] DRY RUN enabled — no state-changing request will reach the broker.' if DhanHQ.configuration.dry_run

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
