# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Supertrend builder' do
  let(:series) do
    cs = CandleSeries.new(symbol: 'TEST')
    100.times do |i|
      price = 100 + i
      cs.add_candle(
        Candle.new(ts: Time.at(i), open: price, high: price + 1, low: price - 1, close: price, volume: 100)
      )
    end
    cs
  end

  context 'with adaptive enabled' do
    before do
      allow(AppSetting).to receive(:fetch_bool).with('use_adaptive_st', default: false).and_return(true)
      allow(AppSetting).to receive(:fetch_int).with('adaptive_st_training',   default: 50).and_return(50)
      allow(AppSetting).to receive(:fetch_int).with('adaptive_st_clusters',   default: 3).and_return(3)
      allow(AppSetting).to receive(:fetch_float).with('adaptive_st_alpha',    default: 0.1).and_return(0.1)
    end

    it 'returns array aligned with series and leading nils during warm up' do
      result = Indicators.build_supertrend(series: series, period: 10, multiplier: 2)
      expect(result.length).to eq(series.candles.length)
      training = AppSetting.fetch_int('adaptive_st_training', default: 50)
      expect(result.first(training)).to all(be_nil)
      expect(result.drop(training).compact).to all(be_a(Float))
    end
  end

  context 'with adaptive disabled' do
    before do
      allow(AppSetting).to receive(:fetch_bool).with('use_adaptive_st', default: false).and_return(false)
    end

    it 'falls back to classic supertrend' do
      classic = Indicators::Supertrend.new(series: series).call
      result = Indicators.build_supertrend(series: series, period: 10, multiplier: 2)
      expect(result).to eq(classic)
    end
  end
end
