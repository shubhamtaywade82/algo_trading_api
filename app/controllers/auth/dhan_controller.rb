# frozen_string_literal: true

module Auth
  class DhanController < ApplicationController
    def login
      redirect_to dhan_login_url, allow_other_host: true
    end

    def callback
      token_response = Dhan::Auth::TokenExchanger.call(params[:code])

      DhanAccessToken.create!(
        access_token: token_response[:access_token],
        expires_at: Time.current + token_response[:expires_in].seconds
      )

      render plain: 'Dhan connected successfully.'
    rescue StandardError => e
      Rails.logger.error("[Auth::DhanController] callback failed: #{e.message}")
      render plain: "Dhan connection failed: #{e.message}", status: :unprocessable_entity
    end

    private

    def dhan_login_url
      query = {
        client_id: dhan_client_id,
        redirect_uri: auth_dhan_callback_url,
        response_type: 'code'
      }.to_query

      "https://api.dhan.co/v2/login?#{query}"
    end

    def dhan_client_id
      ENV.fetch('DHAN_CLIENT_ID', nil) || ENV.fetch('CLIENT_ID', nil)
    end
  end
end
