# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Crypto::Smc::Liquidity do
  def liquidity_for(series)
    described_class.new(series, Crypto::Smc::Structure.new(series, strength: 2))
  end

  describe 'sweeps' do
    it 'reads a wick through the swing high that closes back below as bearish' do
      series = crypto_series([
                               [100, 101, 99, 100],
                               [100, 103, 100, 102],
                               [102, 110, 101, 108],  # pivot high 110
                               [108, 108, 104, 105],
                               [105, 106, 100, 101],
                               [101, 104, 100, 103],
                               [103, 113, 102, 106],  # wick to 113, closes under 110
                               [106, 107, 103, 104],
                               [104, 105, 101, 102]
                             ])

      sweep = liquidity_for(series).recent_sweep(:bearish, lookback: 9)

      expect(sweep).to have_attributes(direction: :bearish, level: 110.0)
      expect(sweep.penetration).to be_within(0.001).of(3.0)
    end

    it 'reads a wick under the swing low that closes back above as bullish' do
      series = crypto_series([
                               [110, 111, 109, 110],
                               [110, 110, 106, 107],
                               [107, 108, 100, 102],  # pivot low 100
                               [102, 106, 101, 105],
                               [105, 109, 104, 108],
                               [108, 109, 105, 106],
                               [106, 107, 97, 105],   # wick to 97, closes above 100
                               [105, 108, 104, 107],
                               [107, 110, 106, 109]
                             ])

      sweep = liquidity_for(series).recent_sweep(:bullish, lookback: 9)

      expect(sweep).to have_attributes(direction: :bullish, level: 100.0)
    end

    it 'does not call a decisive break a sweep' do
      series = crypto_series([
                               [100, 101, 99, 100],
                               [100, 103, 100, 102],
                               [102, 110, 101, 108],  # pivot high 110
                               [108, 108, 104, 105],
                               [105, 106, 100, 101],
                               [101, 104, 100, 103],
                               [103, 114, 102, 113],  # closes ABOVE 110 -> a break
                               [113, 115, 112, 114],
                               [114, 116, 113, 115]
                             ])

      expect(liquidity_for(series).recent_sweep(:bearish, lookback: 9)).to be_nil
    end

    it 'stays quiet on a chart that never raids a level' do
      series = crypto_series(zigzag_bars(legs: 6, amplitude: 4.0))

      expect(liquidity_for(series).sweeps.size).to be < series.size / 4
    end
  end

  describe 'pools' do
    it 'clusters near-identical highs into one pool' do
      series = crypto_series([
                               [100, 101, 99, 100],
                               [100, 103, 100, 102],
                               [102, 110.0, 101, 108],
                               [108, 108, 104, 105],
                               [105, 106, 103, 104],
                               [104, 110.02, 103, 106], # equal high
                               [106, 107, 103, 104],
                               [104, 105, 101, 102],
                               [102, 103, 99, 100]
                             ])

      pool = liquidity_for(series).equal_highs.max_by(&:strength)

      expect(pool.strength).to be >= 2
      expect(pool.price).to be_within(0.05).of(110.0)
    end
  end

  describe 'targets' do
    it 'points at the nearest pool beyond price' do
      series = crypto_series(zigzag_bars(legs: 6, amplitude: 4.0))
      liquidity = liquidity_for(series)
      price = series.last_price

      expect(liquidity.target_above(price)).to be > price if liquidity.target_above(price)
      expect(liquidity.target_below(price)).to be < price if liquidity.target_below(price)
    end
  end
end
