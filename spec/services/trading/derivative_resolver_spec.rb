# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trading::DerivativeResolver, type: :service do
  let(:symbol) { 'NIFTY' }
  let(:expiry) { '2026-03-30' }
  let(:strike) { 22500 }
  let(:option_type) { 'CE' }
  
  subject(:resolver) do
    described_class.new(
      symbol: symbol,
      expiry: expiry,
      strike: strike,
      option_type: option_type
    )
  end

  describe '#call' do
    context 'with valid inputs' do
      it 'resolves the contract from cache or CSV' do
        # Mock the index load and lookup
        allow(described_class).to receive(:load_index!)
        described_class::CACHE["NIFTY:2026-03-30:22500:CE"] = {
          security_id: '12345',
          exchange_segment: 'NSE_FNO',
          trading_symbol: 'NIFTY26MAR22500CE',
          lot_size: 75
        }

        result = resolver.call
        expect(result.security_id).to eq('12345')
        expect(result.trading_symbol).to eq('NIFTY26MAR22500CE')
      end
    end

    context 'with invalid symbol' do
      let(:symbol) { 'INVALID' }
      it 'raises error' do
        expect { resolver.call }.to raise_error(/Invalid symbol/)
      end
    end
  end
end
