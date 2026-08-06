# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'TOKEN_PROVIDER_ONLY mode', :no_dhan_token do
  around do |example|
    original = ENV.fetch('TOKEN_PROVIDER_ONLY', nil)
    example.run
  ensure
    ENV['TOKEN_PROVIDER_ONLY'] = original
  end

  context 'when disabled (default)' do
    before { ENV['TOKEN_PROVIDER_ONLY'] = nil }

    it 'serves trading routes normally' do
      get funds_url

      expect(response).not_to have_http_status(:service_unavailable)
    end
  end

  context 'when enabled' do
    before { ENV['TOKEN_PROVIDER_ONLY'] = 'true' }

    it 'shuts off trading routes' do
      get funds_url

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body['error']).to include('token-provider-only mode')
    end

    it 'still serves the Dhan token endpoint' do
      secret = 'token-api-secret-at-least-24-chars'
      allow(Auth::DhanTokenEndpointSecret).to receive(:configured_secret).and_return(secret)
      DhanAccessToken.delete_all
      DhanAccessToken.create!(access_token: 'jwt.here', expires_at: 1.hour.from_now)

      get auth_dhan_token_url, headers: { 'Authorization' => "Bearer #{secret}" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['access_token']).to eq('jwt.here')
    end

    it 'still serves the Dhan login route' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('DHAN_CLIENT_ID', nil).and_return('client-123')
      allow(ENV).to receive(:fetch).with('CLIENT_ID', nil).and_return(nil)
      allow(ENV).to receive(:fetch).with('DHAN_API_KEY', nil).and_return('api-key')
      allow(ENV).to receive(:fetch).with('DHAN_API_SECRET', nil).and_return('api-secret')
      stub_request(:post, %r{https://auth\.dhan\.co/app/generate-consent})
        .to_return(status: 200, body: { consentAppId: 'abc', status: 'success' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      get auth_dhan_login_url

      expect(response).to have_http_status(:redirect)
    end
  end
end
