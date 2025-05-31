# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Orders::RiskManager, type: :service do
  let(:position) { { 'securityId' => 'OPT123', 'exchangeSegment' => 'NSEFO' } }

  before do
    stub_request(:post, %r{https://api\.telegram\.org/bot[^/]+/sendMessage}).to_return(status: 200, body: '{}')

    allow(Charges::Calculator).to receive(:call).and_return(0)
    allow(Rails.cache).to receive(:read).and_return({ max_pct: analysis[:pnl_pct], danger_zone_count: 0 })
    allow(Rails.cache).to receive(:write)
  end

  context 'when take profit threshold is reached' do
    let(:analysis) do
      { pnl: 5000, pnl_pct: 66.67, entry_price: 100, ltp: 166.67, quantity: 75, instrument_type: :option }
    end

    it 'returns exit with take profit reason' do
      result = described_class.call(position, analysis)
      expect(result[:exit]).to be(true)
      expect(result[:exit_reason]).to match(/TakeProfit/)
    end
  end

  context 'when rupee stop loss is hit but in buffer zone' do
    let(:analysis) { { pnl: -600, pnl_pct: -10, entry_price: 100, ltp: 92, quantity: 75, instrument_type: :option } }

    it 'does NOT exit immediately, due to buffer zone' do
      result = described_class.call(position, analysis)
      expect(result[:exit]).to be(false)
      expect(result[:adjust]).to be(false)
    end
  end

  context 'when rupee stop loss is breached (below danger zone)' do
    let(:analysis) { { pnl: -1100, pnl_pct: -15, entry_price: 100, ltp: 86, quantity: 75, instrument_type: :option } }

    before do
      allow(Rails.cache).to receive(:read).and_return({ max_pct: 10, danger_zone_count: 2 })
      allow(Rails.cache).to receive(:write)
    end

    it 'returns exit when way below danger zone' do
      result = described_class.call(position, analysis)
      expect(result[:exit]).to be(true)
      expect(result[:exit_reason]).to match(/DangerZone|EmergencyStopLoss/)
    end
  end

  context 'when rupee stop loss is in buffer zone (between -1000 and -500)' do
    let(:analysis) { { pnl: -700, pnl_pct: -12, entry_price: 100, ltp: 93, quantity: 75, instrument_type: :option } }

    before do
      # Pretend we're on the 1st bar in danger zone
      allow(Charges::Calculator).to receive(:call).and_return(0)
      allow(Rails.cache).to receive(:read).and_return({ max_pct: 10, danger_zone_count: 1 })
      allow(Rails.cache).to receive(:write)
    end

    it 'does not exit immediately (buffered holding)' do
      result = described_class.call(position, analysis)
      expect(result[:exit]).to be(false)
      expect(result[:adjust]).to be(false)
    end
  end

  context 'when rupee stop loss is breached (below -1000)' do
    let(:analysis) { { pnl: -1100, pnl_pct: -20, entry_price: 100, ltp: 85, quantity: 75, instrument_type: :option } }

    before do
      allow(Charges::Calculator).to receive(:call).and_return(0)
      allow(Rails.cache).to receive(:read).and_return({ max_pct: 10, danger_zone_count: 2 })
      allow(Rails.cache).to receive(:write)
    end

    it 'returns exit with danger zone exit reason' do
      result = described_class.call(position, analysis)
      expect(result[:exit]).to be(true)
      expect(result[:exit_reason]).to match(/DangerZone/)
    end
  end

  context 'when buffered exit triggers after prolonged time in buffer zone' do
    let(:analysis) do
      {
        pnl: -800,
        pnl_pct: -14,
        entry_price: 100,
        ltp: 90,
        quantity: 75,
        instrument_type: :option
        # (optional: order_type: :limit, exit_price: 90.0)
      }
    end

    before do
      # This is the 3rd consecutive bar in the buffer zone
      allow(Charges::Calculator).to receive(:call).and_return(0)
      allow(Rails.cache).to receive(:read).and_return({ max_pct: 10, danger_zone_count: 2 }) # prior was 2, now increments to 3
      allow(Rails.cache).to receive(:write)
    end

    it 'returns exit with danger zone exit after 3 bars' do
      result = described_class.call(position, analysis)
      expect(result[:exit]).to be(true)
      expect(result[:exit_reason]).to match(/DangerZone/)

      expect(result[:order_type]).to eq(:limit)
    end
  end

  context 'when percentage stop loss is hit' do
    let(:analysis) { { pnl: -300, pnl_pct: -35, entry_price: 100, ltp: 96, quantity: 75, instrument_type: :option } }

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
      # Simulate max profit was higher, so drawdown is sufficient
      allow(Rails.cache).to receive(:read).and_return({ max_pct: 40, danger_zone_count: 0 })
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

    it 'returns no exit and no adjust' do
      result = described_class.call(position, analysis)
      expect(result[:exit]).to be(false)
      expect(result[:adjust]).to be(false)
    end
  end

  context 'when break-even trail triggers exit' do
    let(:analysis) { { pnl: 400, pnl_pct: 45, entry_price: 100, ltp: 100, quantity: 75, instrument_type: :option } }

    it 'returns exit with break-even trail reason' do
      result = described_class.call(position, analysis)
      expect(result[:exit]).to be(true)
      expect(result[:exit_reason]).to match(/BreakEven_Trail/)
    end
  end
end
