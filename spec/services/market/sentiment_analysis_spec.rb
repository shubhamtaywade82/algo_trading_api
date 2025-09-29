# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Market::SentimentAnalysis do
  let(:option_chain) { { oc: { '20000.0' => {} }, last_price: 20_000 } }
  let(:expiry) { Date.today.to_s }
  let(:spot) { 20_000 }
  let(:iv_rank) { 0.35 }
  let(:historical_data) { [] }
  let(:strategy_type) { 'intraday' }
  let(:analyzer) { instance_double(Option::ChainAnalyzer) }

  before do
    allow(Option::ChainAnalyzer).to receive(:new).and_return(analyzer)
    allow(analyzer).to receive(:ta).and_return(nil)
  end

  describe '.call' do
    context 'when call side is stronger' do
      let(:call_result) { { proceed: true, selected: { score: 120.5 }, trend: :bullish } }
      let(:put_result)  { { proceed: false, selected: nil, trend: :bullish } }

      before do
        allow(analyzer).to receive(:analyze).with(signal_type: :ce, strategy_type: strategy_type)
                                            .and_return(call_result)
        allow(analyzer).to receive(:analyze).with(signal_type: :pe, strategy_type: strategy_type)
                                            .and_return(put_result)
      end

      it 'reports bullish bias and preferred CE signal' do
        result = described_class.call(
          option_chain: option_chain,
          expiry: expiry,
          spot: spot,
          iv_rank: iv_rank,
          historical_data: historical_data,
          strategy_type: strategy_type
        )

        expect(result[:bias]).to eq(:bullish)
        expect(result[:preferred_signal]).to eq(:ce)
        expect(result[:confidence]).to eq(1.0)
        expect(result[:call_analysis]).to eq(call_result)
        expect(result[:put_analysis]).to eq(put_result)
      end
    end

    context 'when both sides fail' do
      let(:call_result) { { proceed: false, selected: nil, trend: :neutral } }
      let(:put_result)  { { proceed: false, selected: nil, trend: :neutral } }

      before do
        allow(analyzer).to receive(:analyze).and_return(call_result, put_result)
      end

      it 'returns neutral bias with zero confidence' do
        result = described_class.call(
          option_chain: option_chain,
          expiry: expiry,
          spot: spot,
          iv_rank: iv_rank,
          historical_data: historical_data,
          strategy_type: strategy_type
        )

        expect(result[:bias]).to eq(:neutral)
        expect(result[:preferred_signal]).to be_nil
        expect(result[:confidence]).to eq(0.0)
      end
    end
  end
end

