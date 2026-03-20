# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mcp::Tools::ResolveDerivative do
  describe '.execute' do
    let(:expiry_date) { Date.iso8601('2026-03-26') }
    let(:symbol) { 'NIFTY' }
    let(:strike) { 22450 }
    let(:option_type) { 'CE' }

    let(:derivative) do
      instance_double(
        Derivative,
        underlying_symbol: symbol,
        expiry_date: expiry_date,
        strike_price: strike,
        option_type: option_type,
        security_id: '123456',
        exchange_segment: 'NSE_FNO',
        lot_size: 75,
        symbol_name: 'NIFTY26MAR22450CE',
        display_name: nil,
        underlying_security_id: '999'
      )
    end

    let(:instrument) do
      instance_double(
        Instrument,
        fetch_option_chain: option_chain
      )
    end

    let(:option_chain) do
      {
        oc: {
          '22450' => {
            ce: { oi: 2_500, volume: 800 },
            pe: { oi: 100, volume: 10 }
          }
        }
      }
    end

    let(:resolver_result) do
      Trading::DerivativeResolver::Result.new(
        security_id: '123456',
        exchange_segment: 'NSE_FNO',
        trading_symbol: 'NIFTY26MAR22450CE',
        lot_size: 75
      )
    end

    before do
      allow(Trading::DerivativeResolver).to receive(:new).and_return(double(call: resolver_result))
    end

    it 'returns the exact instrument identifiers for the requested option contract' do
      result = described_class.execute(
        'symbol' => symbol,
        'expiry' => expiry_date.to_s,
        'strike' => strike,
        'option_type' => option_type
      )

      expect(result[:security_id]).to eq('123456')
      expect(result[:exchange_segment]).to eq('NSE_FNO')
      expect(result[:trading_symbol]).to eq('NIFTY26MAR22450CE')
      expect(result[:lot_size]).to eq(75)
    end

    it 'rejects invalid option_type' do
      allow(Trading::DerivativeResolver).to receive(:new).and_raise('Invalid option_type')
      
      result = described_class.execute(
        'symbol' => symbol,
        'expiry' => expiry_date.to_s,
        'strike' => strike,
        'option_type' => 'CALL'
      )

      expect(result[:error]).to eq('Invalid option_type')
    end

    it 'fails when contract not found' do
      instance = instance_double(Trading::DerivativeResolver)
      allow(Trading::DerivativeResolver).to receive(:new).and_return(instance)
      allow(instance).to receive(:call).and_raise('Contract not found')

      result = described_class.execute(
        'symbol' => symbol,
        'expiry' => expiry_date.to_s,
        'strike' => strike,
        'option_type' => option_type
      )

      expect(result[:error]).to eq('Contract not found')
    end
  end
end

