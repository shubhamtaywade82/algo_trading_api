require 'rails_helper'

DatabaseCleaner.allow_remote_database_url = true

RSpec.describe Dhan::TokenManager do
  let(:client_id) { 'test_client_id' }
  let(:pin) { '1234' }
  let(:totp_secret) { 'JBSWY3DPEHPK3PXP' }
  let(:new_token) { 'newly_generated_access_token' }
  let(:expiry_time) { 24.hours.from_now.iso8601 }

  before do
    allow(ENV).to receive(:fetch).with('DHAN_CLIENT_ID').and_return(client_id)
    allow(ENV).to receive(:fetch).with('DHAN_PIN').and_return(pin)
    allow(ENV).to receive(:fetch).with('DHAN_TOTP_SECRET').and_return(totp_secret)

    # Mock DhanHQ API
    allow(DhanHQ::Auth).to receive(:generate_totp).and_return('123456')
    allow(DhanHQ::Auth).to receive(:generate_access_token).and_return({
      'accessToken' => new_token,
      'expiryTime' => expiry_time
    })

    # Clear cache and DB
    DhanAccessToken.delete_all
    Rails.cache.clear
  end

  describe '.current_token!' do
    context 'when no token exists in DB' do
      it 'generates a new token via TOTP' do
        expect(DhanHQ::Auth).to receive(:generate_access_token).once
        token = described_class.current_token!
        expect(token).to eq(new_token)
        expect(DhanAccessToken.count).to eq(1)
      end
    end

    context 'when an expired token exists in DB' do
      before do
        DhanAccessToken.create!(access_token: 'expired_token', expires_at: 1.hour.ago)
      end

      it 'refreshes the token' do
        expect(DhanHQ::Auth).to receive(:generate_access_token).once
        token = described_class.current_token!
        expect(token).to eq(new_token)
      end
    end

    context 'when a valid token exists in DB but the local memoization is stale (the bug)' do
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
end
