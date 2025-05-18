# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Orders::RiskManager, type: :service do
  let(:position) { { 'securityId' => 'OPT123', 'exchangeSegment' => 'NSEFO' } }

  context 'when take profit threshold is reached' do
    let(:analysis) do
      { pnl: 5000, pnl_pct: 66.67, entry_price: 100, ltp: 166.67, quantity: 75, instrument_type: :option }
    end

    before do
      allow(Charges::Calculator).to receive(:call).and_return(0)
      allow(Rails.cache).to receive(:read).and_return(analysis[:pnl_pct])
      allow(Rails.cache).to receive(:write)
    end

    it 'returns exit with take profit reason' do
      result = described_class.call(position, analysis)
      expect(result[:exit]).to be(true)
      expect(result[:exit_reason]).to match(/TakeProfit/)
    end
  end

  context 'when rupee stop loss is hit' do
    let(:analysis) { { pnl: -600, pnl_pct: -10, entry_price: 100, ltp: 92, quantity: 75, instrument_type: :option } }

    before do
      allow(Charges::Calculator).to receive(:call).and_return(0)
      allow(Rails.cache).to receive(:read).and_return(analysis[:pnl_pct])
      allow(Rails.cache).to receive(:write)
    end

    it 'returns exit with rupee stop loss reason' do
      result = described_class.call(position, analysis)
      expect(result[:exit]).to be(true)
      expect(result[:exit_reason]).to match(/RupeeStopLoss/)
    end
  end

  context 'when percentage stop loss is hit' do
    let(:analysis) { { pnl: -300, pnl_pct: -35, entry_price: 100, ltp: 96, quantity: 75, instrument_type: :option } }

    before do
      allow(Charges::Calculator).to receive(:call).and_return(0)
      allow(Rails.cache).to receive(:read).and_return(analysis[:pnl_pct])
      allow(Rails.cache).to receive(:write)
    end

    it 'returns exit with percentage stop loss reason' do
      result = described_class.call(position, analysis)
      expect(result[:exit]).to be(true)
      expect(result[:exit_reason]).to match(/StopLoss/)
    end
  end

  context 'when trailing stop adjustment is required' do
    let(:analysis) { { pnl: 400, pnl_pct: 20, entry_price: 100, ltp: 108, quantity: 75, instrument_type: :option } }

    before do
      allow(Charges::Calculator).to receive(:call).and_return(0)
      allow(Rails.cache).to receive(:read).and_return(40) # Max profit previously seen: 40%
      allow(Rails.cache).to receive(:write)
    end

    it 'returns adjust with adjust_params' do
      result = described_class.call(position, analysis)
      expect(result[:adjust]).to be(true)
      expect(result[:adjust_params]).to have_key(:trigger_price)
    end
  end

  context 'when no exit or adjustment is required' do
    let(:analysis) { { pnl: 100, pnl_pct: 5, entry_price: 100, ltp: 101.5, quantity: 75, instrument_type: :option } }

    before do
      allow(Charges::Calculator).to receive(:call).and_return(0)
      allow(Rails.cache).to receive(:read).and_return(analysis[:pnl_pct])
      allow(Rails.cache).to receive(:write)
    end

    it 'returns no exit and no adjust' do
      result = described_class.call(position, analysis)
      expect(result[:exit]).to be(false)
      expect(result[:adjust]).to be(false)
    end
  end

  context 'when break-even trail triggers exit' do
    let(:analysis) { { pnl: 400, pnl_pct: 45, entry_price: 100, ltp: 100, quantity: 75, instrument_type: :option } }

    before do
      allow(Charges::Calculator).to receive(:call).and_return(0)
      allow(Rails.cache).to receive(:read).and_return(50)
      allow(Rails.cache).to receive(:write)
    end

    it 'returns exit with break-even trail reason' do
      result = described_class.call(position, analysis)
      expect(result[:exit]).to be(true)
      expect(result[:exit_reason]).to match(/BreakEven_Trail/)
    end
  end
end
