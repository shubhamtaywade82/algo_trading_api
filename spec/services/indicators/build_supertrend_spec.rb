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
    around do |example|
      orig = ENV['USE_ADAPTIVE_ST']
      ENV['USE_ADAPTIVE_ST'] = 'true'
      example.run
      ENV['USE_ADAPTIVE_ST'] = orig
    end

    it 'returns array aligned with series and leading nils during warm up' do
      result = Indicators.build_supertrend(series: series, period: 10, multiplier: 2)
      expect(result.length).to eq(series.candles.length)
      training = ENV.fetch('ADAPTIVE_ST_TRAINING', '50').to_i
      expect(result.first(training)).to all(be_nil)
      expect(result.drop(training).compact).to all(be_a(Float))
    end
  end

  context 'with adaptive disabled' do
    around do |example|
      orig = ENV['USE_ADAPTIVE_ST']
      ENV['USE_ADAPTIVE_ST'] = 'false'
      example.run
      ENV['USE_ADAPTIVE_ST'] = orig
    end

    it 'falls back to classic supertrend' do
      classic = Indicators::Supertrend.new(series: series).call
      result = Indicators.build_supertrend(series: series, period: 10, multiplier: 2)
      expect(result).to eq(classic)
    end
  end
end
