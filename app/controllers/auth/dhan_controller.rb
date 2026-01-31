# frozen_string_literal: true

module Auth
  class DhanController < ApplicationController
    # STEP 1 + redirect to STEP 2: generate consent, send user to Dhan login.
    def login
      consent_app_id = Dhan::Auth::ConsentGenerator.call
      redirect_to dhan_consent_login_url(consent_app_id), allow_other_host: true
    rescue StandardError => e
      Rails.logger.error("[Auth::DhanController] login failed: #{e.message}")
      render plain: "Dhan login failed: #{e.message}", status: :unprocessable_entity
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

    def dhan_consent_login_url(consent_app_id)
      "https://auth.dhan.co/login/consentApp-login?consentAppId=#{CGI.escape(consent_app_id)}"
    end
  end
end
