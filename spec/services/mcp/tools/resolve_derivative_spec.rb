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

    before do
      allow(Derivative).to receive(:find_by)
        .with(
          underlying_symbol: symbol,
          expiry_date: expiry_date,
          strike_price: strike,
          option_type: option_type
        )
        .and_return(derivative)

      allow(Instrument).to receive(:find_by!)
        .with(security_id: derivative.underlying_security_id.to_s)
        .and_return(instrument)
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
      expect(result[:expiry]).to eq('2026-03-26')
      expect(result[:strike]).to eq(22450)
      expect(result[:option_type]).to eq('CE')
    end

    it 'rejects invalid option_type' do
      result = described_class.execute(
        'symbol' => symbol,
        'expiry' => expiry_date.to_s,
        'strike' => strike,
        'option_type' => 'CALL'
      )

      expect(result[:error]).to eq('Invalid option_type')
    end

    it 'fails when strike is not present in the option chain' do
      bad_chain = { oc: { '99999' => { ce: { oi: 2_500, volume: 800 } } } }
      allow(instrument).to receive(:fetch_option_chain).and_return(bad_chain)

      result = described_class.execute(
        'symbol' => symbol,
        'expiry' => expiry_date.to_s,
        'strike' => strike,
        'option_type' => option_type
      )

      expect(result[:error]).to eq('Strike not present in option chain')
    end

    it 'fails when the contract is illiquid by OI/volume guards' do
      low_liquidity_chain = {
        oc: {
          '22450' => {
            ce: { oi: 10, volume: 20 },
            pe: { oi: 100, volume: 10 }
          }
        }
      }
      allow(instrument).to receive(:fetch_option_chain).and_return(low_liquidity_chain)

      result = described_class.execute(
        'symbol' => symbol,
        'expiry' => expiry_date.to_s,
        'strike' => strike,
        'option_type' => option_type,
        'min_oi' => 1000,
        'min_volume' => 500
      )

      expect(result[:error]).to include('Illiquid strike (low OI')
    end
  end
end

