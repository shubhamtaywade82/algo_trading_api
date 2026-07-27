# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trading::DerivativeResolver, type: :service do
  subject(:resolver) do
    described_class.new(
      symbol: symbol,
      expiry: expiry,
      strike: strike,
      option_type: option_type
    )
  end

  let(:symbol) { 'NIFTY' }
  let(:expiry) { '2026-03-30' }
  let(:strike) { 22_500 }
  let(:option_type) { 'CE' }

  # The rows `bin/rails import:instruments` writes, rather than a hand-seeded
  # in-memory index — the resolver now reads the same table every other contract
  # lookup in the app reads.
  def create_contract(**overrides)
    create(
      :derivative,
      {
        underlying_symbol: 'NIFTY',
        expiry_date: Date.new(2026, 3, 30),
        strike_price: 22_500,
        option_type: 'CE',
        security_id: '12345',
        symbol_name: 'NIFTY26MAR22500CE',
        lot_size: 75,
        exchange: 'nse',
        segment: 'derivatives'
      }.merge(overrides)
    )
  end

  describe '#call' do
    context 'with valid inputs' do
      before { create_contract }

      it 'resolves the contract from the derivatives table' do
        result = resolver.call

        expect(result).to have_attributes(
          security_id: '12345',
          trading_symbol: 'NIFTY26MAR22500CE',
          lot_size: 75
        )
      end

      it 'reports the segment through the model mapping' do
        expect(resolver.call.exchange_segment).to eq('NSE_FNO')
      end
    end

    context 'when the contract is on BSE' do
      before { create_contract(underlying_symbol: 'SENSEX', exchange: 'bse') }

      let(:symbol) { 'SENSEX' }

      it 'resolves it to the BSE derivatives segment' do
        expect(resolver.call.exchange_segment).to eq('BSE_FNO')
      end
    end

    context 'when a different contract of the same underlying exists' do
      before { create_contract(strike_price: 22_600, security_id: '99999') }

      it 'does not resolve to the wrong strike' do
        expect { resolver.call }.to raise_error(/Contract not found/)
      end
    end

    context 'when the contract is absent but others are imported' do
      before { create_contract(underlying_symbol: 'BANKNIFTY') }

      it 'raises without blaming the import' do
        expect { resolver.call }.to raise_error(/Contract not found for NIFTY 2026-03-30 22500 CE\z/)
      end
    end

    context 'when nothing has been imported' do
      it 'points at the import task' do
        expect { resolver.call }.to raise_error(/no derivatives imported.*import:instruments/)
      end
    end

    context 'with invalid symbol' do
      let(:symbol) { 'INVALID' }

      it 'raises error' do
        expect { resolver.call }.to raise_error(/Invalid symbol/)
      end
    end

    context 'with invalid option_type' do
      let(:option_type) { 'XX' }

      it 'raises error' do
        expect { resolver.call }.to raise_error(/Invalid option_type/)
      end
    end

    context 'with a malformed expiry' do
      let(:expiry) { '30-03-2026' }

      it 'raises error' do
        expect { resolver.call }.to raise_error(/Invalid expiry format/)
      end
    end
  end
end
