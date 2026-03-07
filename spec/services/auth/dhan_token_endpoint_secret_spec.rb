# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Auth::DhanTokenEndpointSecret do
  describe '.configured_secret' do
    before do
      allow(Rails.application.credentials).to receive(:dig).with(:dhan, :token_endpoint_secret).and_return(creds_value)
      allow(ENV).to receive(:fetch).with('DHAN_TOKEN_ACCESS_TOKEN', nil).and_return(env_value)
    end

    context 'when credentials have the secret' do
      let(:creds_value) { 'from-credentials-32-chars-long!!!!!' }
      let(:env_value) { 'from-env' }

      it 'returns the credentials value' do
        expect(described_class.configured_secret).to eq(creds_value)
      end
    end

    context 'when credentials are blank and ENV is set' do
      let(:creds_value) { nil }
      let(:env_value) { 'from-env-at-least-24-chars!!' }

      it 'returns the ENV value' do
        expect(described_class.configured_secret).to eq(env_value)
      end
    end

    context 'when both are blank' do
      let(:creds_value) { nil }
      let(:env_value) { nil }

      it 'returns nil' do
        expect(described_class.configured_secret).to be_nil
      end
    end

    context 'in production when secret is shorter than 24 characters' do
      let(:creds_value) { nil }
      let(:env_value) { 'short' }

      it 'returns nil so endpoint is disabled' do
        allow(Rails.env).to receive(:production?).and_return(true)
        expect(described_class.configured_secret).to be_nil
      end
    end

    context 'in production when secret is at least 24 characters' do
      let(:creds_value) { nil }
      let(:env_value) { 'a' * 24 }

      it 'returns the secret' do
        allow(Rails.env).to receive(:production?).and_return(true)
        expect(described_class.configured_secret).to eq('a' * 24)
      end
    end
  end
end
