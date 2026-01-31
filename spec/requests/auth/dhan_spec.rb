# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Auth::Dhan', type: :request do
  describe 'GET /auth/dhan/login' do
    let(:consent_url) { %r{https://auth\.dhan\.co/app/generate-consent\?client_id=client-123} }
    let(:consent_response) { { consentAppId: 'consent-abc', consentAppStatus: 'GENERATED', status: 'success' }.to_json }

    before do
      stub_request(:post, consent_url)
        .with(headers: { 'app_id' => 'api-key', 'app_secret' => 'api-secret' })
        .to_return(status: 200, body: consent_response, headers: { 'Content-Type' => 'application/json' })
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('DHAN_CLIENT_ID', nil).and_return('client-123')
      allow(ENV).to receive(:fetch).with('CLIENT_ID', nil).and_return(nil)
      allow(ENV).to receive(:fetch).with('DHAN_API_KEY', nil).and_return('api-key')
      allow(ENV).to receive(:fetch).with('DHAN_API_SECRET', nil).and_return('api-secret')
    end

    it 'generates consent and redirects to Dhan login with consentAppId' do
      get auth_dhan_login_url

      expect(response).to have_http_status(:redirect)
      expect(response.location).to start_with('https://auth.dhan.co/login/consentApp-login?')
      expect(response.location).to include('consentAppId=consent-abc')
    end
  end

  describe 'GET /auth/dhan/callback' do
    let(:consume_url) { %r{https://auth\.dhan\.co/app/consumeApp-consent\?tokenId=token-xyz} }

    context 'when consent consume succeeds' do
      before do
        stub_request(:get, consume_url)
          .with(headers: { 'app_id' => 'api-key', 'app_secret' => 'api-secret' })
          .to_return(
            status: 200,
            body: {
              accessToken: 'eyJ.test',
              expiryTime: '2026-02-01T12:00:00'
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with('DHAN_API_KEY', nil).and_return('api-key')
        allow(ENV).to receive(:fetch).with('DHAN_API_SECRET', nil).and_return('api-secret')
      end

      it 'creates a DhanAccessToken and returns success' do
        expect { get auth_dhan_callback_url(tokenId: 'token-xyz') }
          .to change(DhanAccessToken, :count).by(1)

        expect(response).to have_http_status(:ok)
        expect(response.body).to eq('Dhan connected successfully.')

        token = DhanAccessToken.last
        expect(token.access_token).to eq('eyJ.test')
        expect(token.expires_at).to be_present
      end
    end

    context 'when tokenId is missing' do
      it 'returns unprocessable_entity and does not create a token' do
        expect { get auth_dhan_callback_url }
          .not_to change(DhanAccessToken, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include('Dhan connection failed')
      end
    end

    context 'when consent consume fails' do
      before do
        stub_request(:get, consume_url)
          .with(headers: { 'app_id' => 'api-key', 'app_secret' => 'api-secret' })
          .to_return(status: 400, body: { message: 'Invalid tokenId' }.to_json)
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with('DHAN_API_KEY', nil).and_return('api-key')
        allow(ENV).to receive(:fetch).with('DHAN_API_SECRET', nil).and_return('api-secret')
      end

      it 'returns unprocessable_entity and does not create a token' do
        expect { get auth_dhan_callback_url(tokenId: 'token-xyz') }
          .not_to change(DhanAccessToken, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include('Dhan connection failed')
      end
    end
  end
end
