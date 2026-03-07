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

          Rails.logger.warn('[DHAN] Regenerating token via TOTP...')

          response = DhanHQ::Auth.generate_access_token(
            dhan_client_id: creds[:client_id],
            pin: creds[:pin],
            totp: generate_totp
          )

          access_token = response.fetch('accessToken')
          expires_at = Time.zone.parse(response.fetch('expiryTime'))

          persist_token(access_token, expires_at)

          Rails.logger.info("[DHAN] Token regenerated successfully. Expires at #{expires_at}")

          access_token
        end
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

      # Loads token state from DB.
      def load_from_db
        record = DhanAccessToken.first
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
