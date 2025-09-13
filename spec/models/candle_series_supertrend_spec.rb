# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandleSeries, '#supertrend_signal' do
  around do |example|
    orig = ENV['USE_ADAPTIVE_ST']
    ENV['USE_ADAPTIVE_ST'] = 'true'
    example.run
    ENV['USE_ADAPTIVE_ST'] = orig
  end

  it 'returns nil when series is shorter than training window' do
    series = described_class.new(symbol: 'TEST')
    10.times do |i|
      price = 100 + i
      series.add_candle(
        Candle.new(ts: Time.at(i), open: price, high: price + 1, low: price - 1, close: price, volume: 100)
      )
    end
    expect(series.supertrend_signal).to be_nil
  end

  it 'returns a trend symbol once warmed up' do
    series = described_class.new(symbol: 'TEST')
    100.times do |i|
      price = 100 + i
      series.add_candle(
        Candle.new(ts: Time.at(i), open: price, high: price + 1, low: price - 1, close: price, volume: 100)
      )
    end
    expect(series.supertrend_signal).to be_in(%i[bullish bearish])
  end
end
