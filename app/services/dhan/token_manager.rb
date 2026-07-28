# app/services/dhan/token_manager.rb

module Dhan
  # Manages Dhan access token lifecycle with DB-backed persistence and advisory locking.
  class TokenManager
    BUFFER_MINUTES = 30
    LOCK_KEY = 424_242
    NOTIFY_CACHE_KEY = 'dhan_token_refresh_notify_lock'.freeze

    class << self
      # Returns a valid access token, refreshing if missing/expiring.
      def current_token!
        token_data = load_from_db

        return refresh!(reason: :missing) if token_data.nil?
        return refresh!(reason: :expired) if expiring?(token_data)

        token_data[:token]
      rescue DhanHQ::InvalidTokenError, DhanHQ::TokenExpiredError
        refresh!(reason: :invalidated)
      end

      # Forces token refresh irrespective of current token state.
      def force_refresh!
        refresh!(reason: :invalidated, force: true)
      end

      # Refreshes token with lock, optionally forcing refresh.
      def refresh!(reason:, force: false)
        with_advisory_lock do
          token_data = load_from_db

          # Double-check after lock unless this is a forced refresh.
          return token_data[:token] if token_data && !force && !expiring?(token_data)

          notify_refresh(reason)

          token_info = fetch_from_local_dashboard || fetch_via_totp
          access_token = token_info[:access_token]
          expires_at = token_info[:expires_at]

          persist_token(access_token, expires_at)

          Rails.logger.info("[DHAN] Token regenerated successfully. Expires at #{expires_at}")

          access_token
        end
      end

      def fetch_from_local_dashboard
        return nil unless should_try_local_dashboard?

        response = request_local_dashboard_token
        return nil unless response&.success?

        parse_local_dashboard_response(response.body)
      rescue StandardError => e
        Rails.logger.warn("[DHAN] Local dashboard token service call failed (#{e.class}: #{e.message}).")
        nil
      end

      def request_local_dashboard_token
        url = ENV['DHAN_TOKEN_SERVICE_URL'].presence || 'http://localhost:3011/api/dhan_access_token'
        bearer = ENV['DHAN_TOKEN_ACCESS_TOKEN'].presence ||
                 ENV['DHAN_DASHBOARD_TOKEN'].presence ||
                 ENV['DASHBOARD_TOKEN'].presence ||
                 'YOUR_DASHBOARD_TOKEN'

        Rails.logger.info("[DHAN] Attempting to fetch access token from remote service (#{url})...")

        Faraday.get(url) do |req|
          req.headers['Authorization'] = "Bearer #{bearer}"
          req.headers['Accept'] = 'application/json'
          req.options.timeout = 5
          req.options.open_timeout = 3
        end
      end

      def parse_local_dashboard_response(body)
        data = begin
          JSON.parse(body.to_s)
        rescue JSON::ParserError
          {}
        end

        token = data['dhan_access_token'] || data['dhanaccesstoken'] || data['accessToken'] || data['access_token']
        raw_expiry = data['expiry_time'] || data['expiryTime'] || data['expires_at']
        return nil if token.blank? || raw_expiry.blank?

        expires_at = Time.zone.parse(raw_expiry.to_s)
        Rails.logger.info("[DHAN] Successfully retrieved access token from remote token service. Expires at #{expires_at}")
        { access_token: token, expires_at: expires_at }
      end

      def fetch_via_totp
        unless allow_totp?
          raise DhanHQ::InvalidAuthenticationError,
                '[DHAN] TOTP token generation is disabled on this instance (DHAN_TOKEN_SERVICE_URL configured or DHAN_ALLOW_TOTP=false) ' \
                'to prevent invalidating the active token on the deployed server.'
        end

        Rails.logger.warn('[DHAN] Regenerating token via TOTP...')

        c = creds
        response = DhanHQ::Auth.generate_access_token(
          dhan_client_id: c[:client_id],
          pin: c[:pin],
          totp: generate_totp
        )

        {
          access_token: extract_access_token(response),
          expires_at: extract_expiry_time(response)
        }
      end

      def allow_totp?
        return false if ENV['DHAN_ALLOW_TOTP'].to_s.downcase == 'false' || ENV['DHAN_DISABLE_TOTP'].to_s.downcase == 'true'

        true
      end

      def should_try_local_dashboard?
        return true if ENV['DHAN_TOKEN_SERVICE_URL'].present? || ENV['DHAN_DASHBOARD_TOKEN'].present? || ENV['DHAN_TOKEN_ACCESS_TOKEN'].present?
        return false if Rails.env.test?

        Rails.env.development?
      end

      # Executes block under PostgreSQL advisory lock.
      def with_advisory_lock
        connection = ActiveRecord::Base.connection

        connection.execute("SELECT pg_advisory_lock(#{LOCK_KEY})")
        yield
      ensure
        connection.execute("SELECT pg_advisory_unlock(#{LOCK_KEY})")
      end

      # Whether token is expiring within safety buffer.
      def expiring?(token_data)
        token_data[:expires_at] <= BUFFER_MINUTES.minutes.from_now
      end

      # Loads token state from DB (most recently created non-expired token; uncached).
      def load_from_db
        record = DhanAccessToken.current_record
        return nil unless record

        {
          token: record.access_token,
          expires_at: record.expires_at
        }
      end

      # Persists current token as single source of truth row.
      def persist_token(token, expires_at)
        DhanAccessToken.transaction do
          DhanAccessToken.delete_all
          DhanAccessToken.create!(
            access_token: token,
            expires_at: expires_at
          )
        end
      end

      # Sends throttled notification on refresh triggers.
      def notify_refresh(reason)
        return if Rails.cache.read(NOTIFY_CACHE_KEY)

        Rails.cache.write(NOTIFY_CACHE_KEY, true, expires_in: 5.minutes)

        message =
          case reason
          when :expired
            '⚠️ Dhan token expired. Regenerating...'
          when :missing
            '⚠️ No Dhan token found. Generating...'
          when :invalidated
            '⚠️ Dhan token invalidated by broker. Regenerating...'
          else
            '⚠️ Dhan token refresh triggered.'
          end

        Rails.logger.warn("[DHAN] #{message}")

        return if ENV['TOKEN_ALERT_CHAT_ID'].blank?

        TelegramNotifier.send_message(
          message,
          chat_id: ENV.fetch('TOKEN_ALERT_CHAT_ID', nil)
        )
      rescue StandardError => e
        Rails.logger.warn("[DHAN] Failed to send token notification: #{e.message}")
      end

      # Generates current TOTP using configured secret.
      def generate_totp
        DhanHQ::Auth.generate_totp(creds[:totp_secret])
      end

      private

      # Extracts access token from API response (string or symbol keys, optional "data" wrapper).
      def extract_access_token(response)
        data = response.is_a?(Hash) ? (response['data'] || response) : {}
        token = data['accessToken'] || data[:accessToken] || data['access_token'] || data[:access_token]
        return token if token.present?

        raise DhanHQ::InvalidAuthenticationError,
              "Dhan token response missing accessToken. Keys: #{safe_response_keys(response)}#{response_hint(response)}"
      end

      def extract_expiry_time(response)
        data = response.is_a?(Hash) ? (response['data'] || response) : {}
        raw = data['expiryTime'] || data[:expiryTime] || data['expiry_time'] || data[:expiry_time]
        if raw.blank?
          raise DhanHQ::InvalidAuthenticationError,
                "Dhan token response missing expiryTime. Keys: #{safe_response_keys(response)}#{response_hint(response)}"
        end

        Time.zone.parse(raw.to_s)
      end

      def safe_response_keys(response)
        return [] unless response.is_a?(Hash)

        top = response.keys.map(&:to_s)
        data = response['data'] || response[:data]
        nested = data.is_a?(Hash) ? data.keys.map(&:to_s) : []
        (top + nested).uniq
      end

      # An empty key list means the SDK handed back nothing to inspect, which
      # says nothing about *why*. Name the shape it did return so the log points
      # somewhere — an empty Hash is the signature of an auth response that came
      # back 2xx and was then dropped unparsed (see the
      # dhan_auth_json_response initializer).
      def response_hint(response)
        return '' unless safe_response_keys(response).empty?

        " (response was #{response.class}#{', empty' if response.respond_to?(:empty?) && response.empty?}; " \
          'a 2xx response with no keys means the body was never parsed)'
      end

      # Required Dhan authentication credentials.
      def creds
        {
          client_id: ENV.fetch('DHAN_CLIENT_ID'),
          pin: ENV.fetch('DHAN_PIN'),
          totp_secret: ENV.fetch('DHAN_TOTP_SECRET')
        }
      end
    end
  end
end
