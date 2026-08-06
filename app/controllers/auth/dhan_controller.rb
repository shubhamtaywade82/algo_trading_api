# frozen_string_literal: true

module Auth
  # Handles Dhan OAuth-style consent flow and token endpoint for API access.
  class DhanController < ApplicationController
    include ActionController::HttpAuthentication::Basic::ControllerMethods

    DASHBOARD_REALM = 'Dhan Token Status'
    MAX_AUTH_FAILURES = 10
    AUTH_LOCKOUT_WINDOW = 5.minutes

    # login/callback are the OAuth-style hand-off with Dhan and would otherwise be
    # public, unauthenticated GETs — anyone could hit /login to mint a consent
    # session with our app_id/app_secret, complete it with their own Dhan account,
    # and let Dhan's redirect land a foreign access_token in our single-row store,
    # silently hijacking the token every other caller then receives. Gating both
    # behind the same Basic Auth as /status closes that: an attacker without the
    # shared secret can't start the flow, and a browser that already authenticated
    # for /login reuses the cached credentials automatically when Dhan redirects
    # back to /callback (same origin, same realm).
    before_action :apply_security_headers
    before_action :authenticate_dashboard_request, only: %i[login callback status]
    before_action :authenticate_token_request, only: :token

    # STEP 1 + redirect to STEP 2: generate consent, send user to Dhan login.
    def login
      consent_app_id = Dhan::Auth::ConsentGenerator.call
      redirect_to dhan_consent_login_url(consent_app_id), allow_other_host: true
    rescue StandardError => e
      Rails.logger.error("[Auth::DhanController] login failed: #{e.message}")
      render plain: "Dhan login failed: #{e.message}", status: :unprocessable_entity
    end

    # Secured API: returns the latest Dhan access token. Ensures token via TokenManager (refresh if needed), then serves from DB.
    def token
      Dhan::TokenManager.current_token!
      record = DhanAccessToken.current_record
      if record.blank?
        notify_telegram_token_missing_once
        return render json: { error: 'No valid Dhan token. Re-login at /auth/dhan/login' }, status: :not_found
      end

      render json: {
        access_token: record.access_token,
        client_id: dhan_client_id,
        expires_at: record.expires_at.iso8601
      }
    rescue StandardError => e
      Rails.logger.error("[Auth::DhanController] token failed: #{e.message}")
      begin
        notify_telegram_token_missing_once
      rescue StandardError
        nil
      end
      render json: { error: 'Token unavailable. Re-login at /auth/dhan/login' }, status: :service_unavailable
    end

    # Browser-facing dashboard: same facts as GET /token, rendered as HTML behind
    # HTTP Basic Auth (so a browser prompts for credentials natively instead of
    # requiring a Bearer header). Never renders the full access token.
    def status
      render plain: status_html(DhanAccessToken.current_record), content_type: 'text/html'
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

    def apply_security_headers
      response.set_header('Cache-Control', 'no-store')
      response.set_header('X-Content-Type-Options', 'nosniff')
      response.set_header('X-Frame-Options', 'DENY')
      response.set_header('Referrer-Policy', 'no-referrer')
      response.set_header('Content-Security-Policy', "default-src 'none'; style-src 'unsafe-inline'")
    end

    def authenticate_token_request
      return if rate_limited?(:token, as: :json)

      expected = Auth::DhanTokenEndpointSecret.configured_secret
      if expected.blank?
        render json: { error: token_endpoint_config_error }, status: :service_unavailable
        return
      end

      bearer = request.authorization.to_s.sub(/\ABearer\s+/i, '').strip
      if ActiveSupport::SecurityUtils.secure_compare(bearer, expected)
        reset_auth_failures(:token)
        return
      end

      register_auth_failure(:token)
      render json: { error: 'Invalid or missing Authorization: Bearer token' }, status: :unauthorized
    end

    def authenticate_dashboard_request
      return if rate_limited?(:dashboard, as: :plain)

      expected = Auth::DhanTokenEndpointSecret.configured_secret
      if expected.blank?
        render plain: token_endpoint_config_error, status: :service_unavailable
        return
      end

      authenticate_or_request_with_http_basic(DASHBOARD_REALM) do |_user, password|
        ok = ActiveSupport::SecurityUtils.secure_compare(password, expected)
        ok ? reset_auth_failures(:dashboard) : register_auth_failure(:dashboard)
        ok
      end
    end

    # Per-IP failure lockout for both auth paths. Rails.cache is process-local
    # memory_store in production (see config/environments/production.rb), so with
    # WEB_CONCURRENCY=2 the effective ceiling is up to 2x MAX_AUTH_FAILURES across
    # workers — an acceptable trade for not adding a shared-store dependency just
    # for this.
    def rate_limited?(bucket, as:)
      return false if auth_failure_count(bucket) < MAX_AUTH_FAILURES

      message = 'Too many failed attempts. Try again later.'
      if as == :json
        render json: { error: message }, status: :too_many_requests
      else
        render plain: message, status: :too_many_requests
      end
      true
    end

    def auth_failure_count(bucket)
      Rails.cache.read(auth_lockout_key(bucket)).to_i
    end

    def register_auth_failure(bucket)
      count = Rails.cache.increment(auth_lockout_key(bucket), 1, expires_in: AUTH_LOCKOUT_WINDOW)
      notify_auth_lockout(bucket) if count == MAX_AUTH_FAILURES
    end

    def reset_auth_failures(bucket)
      Rails.cache.delete(auth_lockout_key(bucket))
    end

    def auth_lockout_key(bucket)
      "dhan_auth_lockout:#{bucket}:#{request.remote_ip}"
    end

    def notify_auth_lockout(bucket)
      return if ENV['TELEGRAM_BOT_TOKEN'].blank? || ENV['TELEGRAM_CHAT_ID'].blank?

      TelegramNotifier.send_message(
        "🚨 #{MAX_AUTH_FAILURES} failed Dhan #{bucket} auth attempts from #{request.remote_ip}. " \
        "Locked out for #{AUTH_LOCKOUT_WINDOW.inspect}."
      )
    rescue StandardError => e
      Rails.logger.warn("[Auth::DhanController] lockout notify failed: #{e.message}")
    end

    def status_html(record)
      remaining_minutes = record ? ((record.expires_at - Time.current) / 60).round : nil
      state = if record.nil?
                'missing'
              else
                remaining_minutes.positive? ? 'active' : 'expired'
              end

      rows = {
        'Status' => %(<span class="badge #{state}">#{state.upcase}</span>),
        'Token' => "<code>#{h(mask_token(record&.access_token))}</code>",
        'Expires at' => record ? "#{h(record.expires_at.iso8601)} (#{remaining_minutes} min remaining)" : '—',
        'Last refreshed' => record ? h(record.created_at.iso8601) : '—',
        'Client ID' => h(dhan_client_id),
        'Mode' => ENV['TOKEN_PROVIDER_ONLY'] == 'true' ? 'Token provider only' : 'Trading enabled'
      }

      <<~HTML
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <title>Dhan Token Status</title>
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; max-width: 640px; margin: 3rem auto; padding: 0 1rem; color: #1a1a1a; }
            h1 { font-size: 1.25rem; }
            table { border-collapse: collapse; width: 100%; margin-top: 1rem; }
            td { padding: 0.5rem 0.75rem; border-bottom: 1px solid #e2e2e2; vertical-align: top; }
            td:first-child { color: #666; width: 40%; }
            .badge { display: inline-block; padding: 0.15rem 0.6rem; border-radius: 999px; font-size: 0.85rem; font-weight: 600; }
            .active { background: #dcfce7; color: #166534; }
            .expired, .missing { background: #fee2e2; color: #991b1b; }
            .meta { color: #888; font-size: 0.8rem; margin-top: 2rem; }
          </style>
        </head>
        <body>
          <h1>Dhan Access Token</h1>
          <table>
            #{rows.map { |k, v| "<tr><td>#{h(k)}</td><td>#{v}</td></tr>" }.join}
          </table>
          <p class="meta">Rendered at #{h(Time.current.iso8601)}</p>
        </body>
        </html>
      HTML
    end

    def mask_token(token)
      return '—' if token.blank?
      return token if token.length <= 12

      "#{token[0..7]}…#{token[-4..]}"
    end

    def h(text)
      CGI.escapeHTML(text.to_s)
    end

    def token_endpoint_config_error
      return 'Token endpoint not configured' unless Rails.env.production?

      'Token endpoint not configured. Set a secret of at least 24 characters ' \
        '(ENV DHAN_TOKEN_ACCESS_TOKEN or credentials dhan.token_endpoint_secret).'
    end

    def dhan_client_id
      ENV.fetch('DHAN_CLIENT_ID', nil) || ENV.fetch('CLIENT_ID', nil)
    end

    # Rate-limited: at most once per hour when token endpoint returns 404 or 503 (no/missing token).
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
