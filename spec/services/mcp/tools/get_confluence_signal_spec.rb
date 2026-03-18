# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mcp::Tools::GetConfluenceSignal do
  describe '.execute' do
    let(:segment_index) { instance_double(ActiveRecord::Relation) }
    let(:instrument) { instance_double(Instrument) }

    before do
      allow(Instrument).to receive(:segment_index).and_return(segment_index)
      allow(segment_index).to receive(:find_by).and_return(instrument)
    end

    it 'returns nil signal when ConfluenceDetector returns nil' do
      allow(instrument).to receive(:candle_series).and_return(instance_double('CandleSeries', candles: []))
      allow(Market::ConfluenceDetector).to receive(:call).and_return(nil)

      result = described_class.execute('symbol' => 'NIFTY', 'interval' => '5')
      expect(result[:signal]).to be_nil
      expect(result[:reason]).to include('No confluence threshold')
    end

    it 'formats signal when ConfluenceDetector returns a signal' do
      factor = Market::ConfluenceDetector::Factor.new(name: 'EMA20', value: 1, note: 'Above')
      signal = Market::ConfluenceDetector::ConfluenceSignal.new(
        symbol: 'NIFTY',
        bias: :bullish,
        net_score: 6,
        max_score: 14,
        level: :medium,
        factors: [factor],
        close: 22000.0,
        atr: 50.0,
        timestamp: Time.current
      )

      candles = [
        Candle.new(ts: Time.current, open: 1, high: 2, low: 0, close: 1, volume: 10)
      ]

      allow(instrument).to receive(:candle_series).and_return(instance_double('CandleSeries', candles: candles))
      allow(Market::ConfluenceDetector).to receive(:call).and_return(signal)

      result = described_class.execute('symbol' => 'NIFTY')

      expect(result[:symbol]).to eq('NIFTY')
      expect(result[:bias]).to eq('bullish')
      expect(result[:net_score]).to eq(6)
      expect(result[:level]).to eq('medium')
      expect(result[:factors].first[:name]).to eq('EMA20')
    end
  end
end

