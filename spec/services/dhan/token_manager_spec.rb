require 'rails_helper'

DatabaseCleaner.allow_remote_database_url = true

RSpec.describe Dhan::TokenManager do
  let(:client_id) { 'test_client_id' }
  let(:pin) { '1234' }
  let(:totp_secret) { 'JBSWY3DPEHPK3PXP' }
  let(:new_token) { 'newly_generated_access_token' }
  let(:expiry_time) { 24.hours.from_now.iso8601 }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('DHAN_CLIENT_ID').and_return(client_id)
    allow(ENV).to receive(:fetch).with('DHAN_PIN').and_return(pin)
    allow(ENV).to receive(:fetch).with('DHAN_TOTP_SECRET').and_return(totp_secret)

    # Mock DhanHQ API
    allow(DhanHQ::Auth).to receive_messages(generate_totp: '123456', generate_access_token: {
                                              'accessToken' => new_token,
                                              'expiryTime' => expiry_time
                                            })

    # Clear cache and DB
    DhanAccessToken.delete_all
    Rails.cache.clear
  end

  describe '.current_token!' do
    context 'when no token exists in DB', :no_dhan_token do
      it 'generates a new token via TOTP' do
        expect(DhanHQ::Auth).to receive(:generate_access_token).once
        token = described_class.current_token!
        expect(token).to eq(new_token)
        expect(DhanAccessToken.count).to eq(1)
      end
    end

    context 'when an expired token exists in DB', :no_dhan_token do
      before do
        DhanAccessToken.create!(access_token: 'expired_token', expires_at: 1.hour.ago)
      end

      it 'refreshes the token' do
        expect(DhanHQ::Auth).to receive(:generate_access_token).once
        token = described_class.current_token!
        expect(token).to eq(new_token)
      end
    end

    context 'when a valid token exists in DB but the local memoization is stale (the bug)', :no_dhan_token do
      it 'picks up the new token from the database' do
        # 1. First call loads a token into memoization
        DhanAccessToken.create!(access_token: 'valid_token_1', expires_at: 1.hour.from_now)
        described_class.current_token!

        # 2. Simulate another process/worker updating the DB with a newer token
        # (We bypass TokenManager here to simulate "external" update)
        DhanAccessToken.delete_all
        DhanAccessToken.create!(access_token: 'valid_token_2', expires_at: 2.hours.from_now)

        # 3. Before the fix, this would still return 'valid_token_1' because of @cached_token
        # After the fix, it should return 'valid_token_2'
        expect(described_class.current_token!).to eq('valid_token_2')
      end
    end
  end

  describe 'token response parsing' do
    context 'when API response has no accessToken' do
      before do
        allow(DhanHQ::Auth).to receive(:generate_access_token).and_return(
          { 'status' => 'error', 'message' => 'Invalid TOTP' }
        )
      end

      it 'raises InvalidAuthenticationError with response keys in message' do
        expect do
          described_class.refresh!(reason: :missing)
        end.to raise_error(DhanHQ::InvalidAuthenticationError, /missing accessToken.*Keys:.*status.*message/)
      end
    end

    context 'when API response nests token under data' do
      before do
        allow(DhanHQ::Auth).to receive(:generate_access_token).and_return(
          'data' => {
            'accessToken' => 'nested_token',
            'expiryTime' => 24.hours.from_now.iso8601
          }
        )
      end

      it 'extracts token and expiry from nested data' do
        token = described_class.refresh!(reason: :missing)
        expect(token).to eq('nested_token')
        expect(DhanAccessToken.first.access_token).to eq('nested_token')
      end
    end
  end

  # The examples above hand DhanHQ::Auth a ready-made Hash, which is precisely
  # the assumption that broke in production: the SDK never parses its auth
  # response, so a 2xx handshake reached this class as `{}` and the boot failed
  # with "missing accessToken. Keys: []". Drive the whole path over HTTP so the
  # decode step in config/initializers/dhan_auth_json_response.rb is covered.
  describe 'end-to-end handshake', :no_dhan_token do
    before { allow(DhanHQ::Auth).to receive(:generate_access_token).and_call_original }

    it 'persists the token returned by a successful handshake' do
      expiry = 24.hours.from_now.change(usec: 0)
      stub_request(:post, /auth\.dhan\.co/).to_return(
        status: 200,
        body: { dhanClientId: '1101', accessToken: 'live.jwt.token',
                expiryTime: expiry.iso8601 }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

      expect(described_class.refresh!(reason: :missing)).to eq('live.jwt.token')
      expect(DhanAccessToken.first).to have_attributes(
        access_token: 'live.jwt.token',
        expires_at: expiry
      )
    end

    it 'raises with the broker message when the handshake is rejected' do
      stub_request(:post, /auth\.dhan\.co/).to_return(
        status: 401,
        body: { errorMessage: 'Invalid TOTP' }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

      expect { described_class.refresh!(reason: :missing) }
        .to raise_error(DhanHQ::InvalidAuthenticationError, /Invalid TOTP/)
      expect(DhanAccessToken.count).to eq(0)
    end
  end

  describe 'local dashboard token service' do
    let(:dashboard_token) { 'MY_SECRET_DASHBOARD_BEARER' }
    let(:local_url) { 'http://localhost:3011/api/dhan_access_token' }
    let(:expiry) { 24.hours.from_now.change(usec: 0) }

    before do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('DHAN_DASHBOARD_TOKEN').and_return(dashboard_token)
      allow(ENV).to receive(:[]).with('DHAN_TOKEN_SERVICE_URL').and_return(local_url)
    end

    it 'fetches and persists token from local dashboard endpoint when available' do
      stub_request(:get, local_url)
        .with(headers: { 'Authorization' => "Bearer #{dashboard_token}" })
        .to_return(
          status: 200,
          body: {
            dhan_access_token: 'local_dash_jwt_token',
            expiry_time: expiry.iso8601
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      expect(described_class.refresh!(reason: :missing)).to eq('local_dash_jwt_token')
      expect(DhanAccessToken.first).to have_attributes(
        access_token: 'local_dash_jwt_token',
        expires_at: expiry
      )
    end

    it 'falls back to TOTP when local dashboard request fails' do
      stub_request(:get, local_url).to_return(status: 500)

      expect(DhanHQ::Auth).to receive(:generate_access_token).once
      expect(described_class.refresh!(reason: :missing)).to eq(new_token)
    end
  end

  describe 'diagnostics' do
    it 'names the empty response so an unparsed body is identifiable in the log' do
      allow(DhanHQ::Auth).to receive(:generate_access_token).and_return({})

      expect { described_class.refresh!(reason: :missing) }
        .to raise_error(DhanHQ::InvalidAuthenticationError, /body was never parsed/)
    end
  end
end
