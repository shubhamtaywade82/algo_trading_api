# app/services/dhan/token_manager.rb

module Dhan
  class TokenManager
    BUFFER_MINUTES = 30
    LOCK_KEY = 424_242

    class << self
      def current_token!
        token_data = cached_token

        if token_data.nil? || expiring?(token_data)
          refresh!
          token_data = cached_token
        end

        token_data[:token]
      end

      def refresh!
        with_advisory_lock do
          token_data = load_from_db

          # Double-check after acquiring lock
          return token_data[:token] if token_data && !expiring?(token_data)

          Rails.logger.info '[DHAN] Regenerating token via TOTP...'

          response = DhanHQ::Auth.generate_access_token(
            dhan_client_id: creds[:client_id],
            pin: creds[:pin],
            totp: generate_totp
          )

          access_token = response['accessToken']
          expires_at = Time.zone.parse(response['expiryTime'])

          persist_token(access_token, expires_at)
          cache_token(access_token, expires_at)

          access_token
        end
      end

      def force_refresh!
        with_advisory_lock do
          Rails.logger.warn "[DHAN] Force regenerating token due to invalidation..."

          response = DhanHQ::Auth.generate_access_token(
            dhan_client_id: creds[:client_id],
            pin: creds[:pin],
            totp: generate_totp
          )

          access_token = response["accessToken"]
          expires_at  = Time.parse(response["expiryTime"])

          persist_token(access_token, expires_at)
          cache_token(access_token, expires_at)

          access_token
        end
      end

      private

      # ===============================
      # Multi-process safe locking
      # ===============================

      def with_advisory_lock
        ActiveRecord::Base.connection.execute(
          "SELECT pg_advisory_lock(#{LOCK_KEY})"
        )

        yield
      ensure
        ActiveRecord::Base.connection.execute(
          "SELECT pg_advisory_unlock(#{LOCK_KEY})"
        )
      end

      # ===============================
      # In-memory cache (per worker)
      # ===============================

      def cached_token
        @cached_token ||= load_from_db
      end

      def cache_token(token, expires_at)
        @cached_token = {
          token: token,
          expires_at: expires_at
        }
      end

      def expiring?(token_data)
        token_data[:expires_at] <= BUFFER_MINUTES.minutes.from_now
      end

      # ===============================
      # DB source of truth
      # ===============================

      def load_from_db
        record = DhanAccessToken.active
        return nil unless record

        {
          token: record.access_token,
          expires_at: record.expires_at
        }
      end

      def persist_token(token, expires_at)
        DhanAccessToken.transaction do
          DhanAccessToken.delete_all
          DhanAccessToken.create!(
            access_token: token,
            expires_at: expires_at
          )
        end
      end

      def generate_totp
        DhanHQ::Auth.generate_totp(creds[:totp_secret])
      end

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
