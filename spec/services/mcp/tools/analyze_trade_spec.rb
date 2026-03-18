# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mcp::Tools::AnalyzeTrade do
  describe '.execute' do
    it 'returns trade decision result with ISO8601 timestamp' do
      timestamp = Time.zone.parse('2026-03-18 10:05:00')
      regime = Trading::RegimeScorer::Result.new(state: :tradeable, trend: :bullish, reason: nil)
      chain_analysis = { proceed: true, reason: nil, selected: { strike: 22000 } }
      selected_strike = { strike: 22000, option_type: 'CE', last_price: 120.0 }

      result_struct = Trading::TradeDecisionEngine::Result.new(
        proceed: true,
        symbol: 'NIFTY',
        direction: 'CE',
        expiry: '2026-03-27',
        selected_strike: selected_strike,
        iv_rank: 40.0,
        regime: regime,
        chain_analysis: chain_analysis,
        spot: 22000.0,
        reason: nil,
        timestamp: timestamp
      )

      allow(Trading::TradeDecisionEngine).to receive(:call).with(symbol: 'NIFTY', expiry: nil).and_return(result_struct)

      result = described_class.execute('symbol' => 'NIFTY')
      expect(result[:proceed]).to be true
      expect(result[:direction]).to eq('CE')
      expect(result[:timestamp]).to eq(timestamp.iso8601)
      expect(result[:selected_strike]).to eq(selected_strike)
      expect(result[:strike]).to eq(22000)
      expect(result[:entry]).to eq(120.0)
      expect(result[:sl]).to eq(96.95) # 120 * (1 - sl_pct(=0.192)) rounded to tick
      expect(result[:tp]).to eq(158.4)  # 120 * (1 + tp_pct(=0.32)) rounded to tick
    end
  end
end

