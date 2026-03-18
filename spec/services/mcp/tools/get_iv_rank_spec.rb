# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mcp::Tools::GetIvRank do
  describe '.execute' do
    let(:instrument) do
      instance_double(
        Instrument,
        expiry_list: ['2026-03-27'],
        fetch_option_chain: { oc: {} }
      )
    end

    before do
      segment_index = instance_double(ActiveRecord::Relation)
      allow(Instrument).to receive(:segment_index).and_return(segment_index)
      allow(segment_index).to receive(:find_by)
        .with(underlying_symbol: 'NIFTY', exchange: 'nse')
        .and_return(instrument)

      allow(Option::ChainAnalyzer).to receive(:estimate_iv_rank).and_return(0.42)
    end

    it 'returns iv_rank_pct and regime bucket' do
      result = described_class.execute('symbol' => 'NIFTY')
      expect(result[:iv_rank_pct]).to eq(42.0)
      expect(result[:iv_regime]).to eq('normal')
      expect(result[:expiry]).to eq('2026-03-27')
    end
  end
end

