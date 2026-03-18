# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mcp::Tools::GetMarketSentiment do
  describe '.execute' do
    let(:vix_instrument) { instance_double(Instrument, ltp: 12.0) }

    let(:option_chain) do
      {
        last_price: 22000.0,
        oc: {
          '22000.000000' => {
            'ce' => { 'oi' => 100_000, 'implied_volatility' => 0.15 },
            'pe' => { 'oi' => 130_000, 'implied_volatility' => 0.18 }
          }
        }
      }
    end

    let(:instrument) do
      instance_double(
        Instrument,
        ltp: 22000.0,
        expiry_list: ['2026-03-27'],
        fetch_option_chain: option_chain
      )
    end

    before do
      segment_index = instance_double(ActiveRecord::Relation)
      allow(Instrument).to receive(:segment_index).and_return(segment_index)
      allow(segment_index).to receive(:find_by).with(underlying_symbol: 'NIFTY', exchange: 'nse').and_return(instrument)

      allow(Instrument).to receive(:find_by).with(security_id: 21).and_return(vix_instrument)
      allow(Option::ChainAnalyzer).to receive(:estimate_iv_rank).and_return(0.30)
      allow(Option::HistoricalDataFetcher).to receive(:for_strategy).and_return([])
      allow(Market::SentimentAnalysis).to receive(:call).and_return({ bias: 'bearish' })
    end

    it 'returns bias and PCR derived values' do
      result = described_class.execute('symbol' => 'NIFTY')

      expect(result[:symbol]).to eq('NIFTY')
      expect(result[:vix]).to eq(12.0)
      expect(result[:vix_level]).to eq('elevated')
      expect(result[:pcr]).to be_within(0.001).of(1.3)
      expect(result[:bias]).to eq('bullish')
      expect(result[:sentiment]).to eq('bearish')
    end
  end
end

