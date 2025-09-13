# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandleSeries, '#supertrend_signal' do
  before do
    allow(AppSetting).to receive(:fetch_bool).with('use_adaptive_st', default: false).and_return(true)
    allow(AppSetting).to receive(:fetch_int).with('adaptive_st_training',   default: 50).and_return(50)
    allow(AppSetting).to receive(:fetch_int).with('adaptive_st_clusters',   default: 3).and_return(3)
    allow(AppSetting).to receive(:fetch_float).with('adaptive_st_alpha',    default: 0.1).and_return(0.1)
    allow(AppSetting).to receive(:fetch_int).with('supertrend_period', default: 10).and_return(10)
    allow(AppSetting).to receive(:fetch_float).with('supertrend_multiplier', default: 2.0).and_return(2.0)
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
