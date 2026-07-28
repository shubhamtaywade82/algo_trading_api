# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Crypto::Series do
  describe '#swing_highs' do
    it 'finds the pivot and reports when it became knowable' do
      # bar 2 is the peak; with strength 2 it is only confirmed at bar 4
      series = crypto_series([
                               [100, 101, 99, 100],
                               [100, 103, 100, 102],
                               [102, 110, 101, 108],
                               [108, 106, 104, 105],
                               [105, 104, 102, 103]
                             ])

      pivots = series.swing_highs(strength: 2)

      expect(pivots.size).to eq(1)
      expect(pivots.first).to include(index: 2, price: 110.0, confirmed_at: 4)
    end

    it 'ignores a peak that has too few bars to its right to confirm' do
      series = crypto_series([
                               [100, 101, 99, 100],
                               [100, 103, 100, 102],
                               [102, 110, 101, 108],
                               [108, 106, 104, 105]
                             ])

      expect(series.swing_highs(strength: 2)).to be_empty
    end
  end

  describe '#swing_lows' do
    it 'finds the trough' do
      series = crypto_series([
                               [100, 101, 99, 100],
                               [100, 100, 96, 97],
                               [97, 98, 90, 92],
                               [92, 96, 93, 95],
                               [95, 99, 94, 98]
                             ])

      pivots = series.swing_lows(strength: 2)

      expect(pivots.pluck(:price)).to eq([90.0])
    end
  end

  describe '#atr' do
    it 'is zero when there is not enough history to measure a range' do
      expect(crypto_series([[100, 101, 99, 100]]).atr).to eq(0.0)
    end

    it 'averages the true range of the last n bars' do
      series = crypto_series([
                               [100, 102, 98, 100],
                               [100, 104, 100, 103],
                               [103, 105, 101, 102]
                             ])

      # TRs: max(4, 4, 0)=4 then max(4, 2, 2)=4
      expect(series.atr(2)).to eq(4.0)
    end
  end

  describe '#from_binance' do
    it 'builds candles from raw kline rows without tick-rounding the price' do
      rows = binance_rows([[145.123, 146.987, 144.001, 146.456]])
      series = described_class.from_binance(symbol: 'SOLUSDT', timeframe: '5m', rows: rows)

      expect(series.size).to eq(1)
      expect(series.last.close).to eq(146.456)
      expect(series.last.volume).to eq(1000.5)
    end
  end
end
