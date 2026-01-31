# frozen_string_literal: true

module Auth
  class DhanController < ApplicationController
    before_action :authenticate_token_request, only: :token

    # STEP 1 + redirect to STEP 2: generate consent, send user to Dhan login.
    def login
      consent_app_id = Dhan::Auth::ConsentGenerator.call
      redirect_to dhan_consent_login_url(consent_app_id), allow_other_host: true
    rescue StandardError => e
      Rails.logger.error("[Auth::DhanController] login failed: #{e.message}")
      render plain: "Dhan login failed: #{e.message}", status: :unprocessable_entity
    end

    # Secured API: returns the latest active Dhan access token (farthest expiry). Requires Bearer token.
    def token
      record = DhanAccessToken.active
      if record.blank?
        notify_telegram_token_missing_once
        return render json: { error: 'No valid Dhan token. Re-login at /auth/dhan/login' }, status: :not_found
      end

      render json: {
        access_token: record.access_token,
        client_id: dhan_client_id,
        expires_at: record.expires_at.iso8601
      }
    end

    # STEP 3: Dhan redirects here with tokenId; exchange for access token and store.
    def callback
      token_id = params[:tokenId]
      raise ArgumentError, 'missing tokenId' if token_id.blank?

      token_response = Dhan::Auth::ConsentConsumer.call(token_id)

      DhanAccessToken.create!(
        access_token: token_response[:access_token],
        expires_at: token_response[:expires_at]
      )

      render plain: 'Dhan connected successfully.'
    rescue StandardError => e
      Rails.logger.error("[Auth::DhanController] callback failed: #{e.message}")
      render plain: "Dhan connection failed: #{e.message}", status: :unprocessable_entity
    end

    private

    def authenticate_token_request
      expected = ENV.fetch('DHAN_TOKEN_ACCESS_TOKEN', nil)
      if expected.blank?
        render json: { error: 'Token endpoint not configured' }, status: :service_unavailable
        return
      end

      bearer = request.authorization.to_s.sub(/\ABearer\s+/i, '').strip
      return if ActiveSupport::SecurityUtils.secure_compare(bearer, expected)

      render json: { error: 'Invalid or missing Authorization: Bearer token' }, status: :unauthorized
    end

    def dhan_client_id
      ENV.fetch('DHAN_CLIENT_ID', nil) || ENV.fetch('CLIENT_ID', nil)
    end

    # Rate-limited: at most once per hour when token endpoint returns 404.
    def notify_telegram_token_missing_once
      return unless ENV['TELEGRAM_BOT_TOKEN'].present? && ENV['TELEGRAM_CHAT_ID'].present?

      cache_key = 'dhan_token_missing_notified_at'
      return if Rails.cache.exist?(cache_key)

      login_url = "#{request.base_url}#{Rails.application.routes.url_helpers.auth_dhan_login_path}"
      opts = { parse_mode: 'Markdown' }
      opts[:reply_markup] = { inline_keyboard: [[{ text: 'Re-login', url: login_url }]] } if TelegramNotifier.public_url?(login_url)
      TelegramNotifier.send_message(
        "🔐 Dhan token missing or expired. [Re-login here](#{login_url}) to restore.",
        **opts
      )
      Rails.cache.write(cache_key, Time.current, expires_in: 1.hour)
    rescue StandardError => e
      Rails.logger.warn("[Auth::DhanController] Telegram notify failed: #{e.message}")
    end

    def dhan_consent_login_url(consent_app_id)
      "https://auth.dhan.co/login/consentApp-login?consentAppId=#{CGI.escape(consent_app_id)}"
    end
  end
end
