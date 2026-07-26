# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Dhan::CandleNormalizer do
  describe '.columnar' do
    # Shape returned by DhanHQ >= 3.0 HistoricalData.daily/.intraday
    let(:sdk_candles) do
      [
        { timestamp: Time.zone.at(1_700_000_000), open: 100.0, high: 105.0, low: 99.0, close: 104.0, volume: 1_000 },
        { timestamp: Time.zone.at(1_700_000_300), open: 104.0, high: 108.0, low: 103.0, close: 107.0, volume: 1_500 }
      ]
    end

    it 'folds an array of candle hashes into columnar arrays' do
      result = described_class.columnar(sdk_candles)

      expect(result['open']).to eq([100.0, 104.0])
      expect(result['high']).to eq([105.0, 108.0])
      expect(result['low']).to eq([99.0, 103.0])
      expect(result['close']).to eq([104.0, 107.0])
      expect(result['volume']).to eq([1_000, 1_500])
    end

    it 'emits timestamps as epoch integers so callers can Time.zone.at them' do
      result = described_class.columnar(sdk_candles)

      expect(result['timestamp']).to eq([1_700_000_000, 1_700_000_300])
      expect(Time.zone.at(result['timestamp'].first)).to eq(Time.zone.at(1_700_000_000))
    end

    it 'exposes columns under both string and symbol keys' do
      result = described_class.columnar(sdk_candles)

      expect(result[:close]).to eq(result['close'])
    end

    it 'includes open_interest only when the SDK returned it' do
      without_oi = described_class.columnar(sdk_candles)
      with_oi = described_class.columnar(
        sdk_candles.each_with_index.map { |c, i| c.merge(open_interest: 10 + i) }
      )

      expect(without_oi).not_to have_key('open_interest')
      expect(with_oi['open_interest']).to eq([10, 11])
    end

    it 'passes a pre-3.0 columnar hash through unchanged' do
      legacy = { 'open' => [100.0], 'close' => [104.0], 'timestamp' => [1_700_000_000] }

      expect(described_class.columnar(legacy)['close']).to eq([104.0])
    end

    it 'returns nil for blank or non-candle payloads' do
      expect(described_class.columnar(nil)).to be_nil
      expect(described_class.columnar([])).to be_nil
      expect(described_class.columnar('nope')).to be_nil
      expect(described_class.columnar([1, 2, 3])).to be_nil
    end

    it 'produces a payload Market::CandleLoader can consume' do
      series = CandleSeries.new(symbol: 'NIFTY', interval: '5')
      series.load_from_raw(described_class.columnar(sdk_candles))

      expect(series.candles.size).to eq(2)
      expect(series.closes).to eq([104.0, 107.0])
    end
  end
end
