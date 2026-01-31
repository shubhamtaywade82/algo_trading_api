# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Auth::Dhan', type: :request do
  describe 'GET /auth/dhan/login' do
    before do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('DHAN_CLIENT_ID', nil).and_return('client-123')
      allow(ENV).to receive(:fetch).with('CLIENT_ID', nil).and_return(nil)
    end

    it 'redirects to Dhan login URL with client_id and callback' do
      get auth_dhan_login_url

      expect(response).to have_http_status(:redirect)
      expect(response.location).to start_with('https://api.dhan.co/v2/login?')
      expect(response.location).to include('client_id=client-123')
      expect(response.location).to include('redirect_uri=')
      expect(response.location).to include('response_type=code')
    end
  end

  describe 'GET /auth/dhan/callback' do
    let(:token_url) { 'https://api.dhan.co/v2/token' }

    context 'when token exchange succeeds' do
      before do
        stub_request(:post, token_url)
          .with(
            body: hash_including(clientId: 'cid', clientSecret: 'secret', code: 'auth-code'),
            headers: { 'Content-Type' => 'application/json' }
          )
          .to_return(
            status: 200,
            body: { accessToken: 'eyJ.test', expiresIn: 86_400 }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with('DHAN_CLIENT_ID', nil).and_return('cid')
        allow(ENV).to receive(:fetch).with('CLIENT_ID', nil).and_return(nil)
        allow(ENV).to receive(:fetch).with('DHAN_CLIENT_SECRET', nil).and_return('secret')
        allow(ENV).to receive(:fetch).with('DHAN_API_SECRET', nil).and_return(nil)
      end

      it 'creates a DhanAccessToken and returns success' do
        expect { get auth_dhan_callback_url(code: 'auth-code') }
          .to change(DhanAccessToken, :count).by(1)

        expect(response).to have_http_status(:ok)
        expect(response.body).to eq('Dhan connected successfully.')

        token = DhanAccessToken.last
        expect(token.access_token).to eq('eyJ.test')
        expect(token.expires_at).to be_within(2.seconds).of(86_400.seconds.from_now)
      end
    end

    context 'when token exchange fails' do
      before do
        stub_request(:post, token_url).to_return(status: 400, body: { message: 'Invalid code' }.to_json)
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with('DHAN_CLIENT_ID', nil).and_return('cid')
        allow(ENV).to receive(:fetch).with('CLIENT_ID', nil).and_return(nil)
        allow(ENV).to receive(:fetch).with('DHAN_CLIENT_SECRET', nil).and_return('secret')
        allow(ENV).to receive(:fetch).with('DHAN_API_SECRET', nil).and_return(nil)
      end

      it 'returns unprocessable_entity and does not create a token' do
        expect { get auth_dhan_callback_url(code: 'bad-code') }
          .not_to change(DhanAccessToken, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include('Dhan connection failed')
      end
    end
  end
end
