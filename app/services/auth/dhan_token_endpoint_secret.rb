# frozen_string_literal: true

module Auth
  # Provides the Bearer secret for GET /auth/dhan/token.
  # Prefers Rails credentials (encrypted); falls back to ENV. Rejects weak secrets in production.
  class DhanTokenEndpointSecret
    MIN_LENGTH = 24
    ENV_KEY = 'DHAN_TOKEN_ACCESS_TOKEN'
    CREDENTIALS_PATH = %i[dhan token_endpoint_secret].freeze

    class << self
      # Returns the configured secret, or nil if missing/weak (production only).
      def configured_secret
        raw = from_credentials.presence || ENV.fetch(ENV_KEY, nil)
        return raw if raw.blank?
        return raw if !Rails.env.production?
        return nil if raw.length < MIN_LENGTH

        raw
      end

      private

      def from_credentials
        Rails.application.credentials.dig(*CREDENTIALS_PATH)
      end
    end
  end
end
