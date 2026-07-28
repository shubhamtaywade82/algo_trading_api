# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Crypto::Smc::FairValueGaps do
  it 'records a bullish gap where the third bar leaves the first behind' do
    # bar 0 high 101, bar 2 low 105 -> imbalance 101..105
    series = crypto_series([
                             [100, 101, 99, 100],
                             [100, 106, 100, 105],
                             [105, 110, 105, 109],
                             [109, 111, 108, 110],
                             [110, 112, 109, 111]
                           ])

    gap = described_class.new(series).bullish.first

    expect(gap).to have_attributes(direction: :bullish, bottom: 101.0, top: 105.0)
    expect(gap.invalidated?).to be(false)
  end

  it 'records a bearish gap' do
    series = crypto_series([
                             [110, 111, 109, 110],
                             [110, 110, 104, 105],
                             [105, 104, 100, 101],
                             [101, 102, 99, 100],
                             [100, 101, 98, 99]
                           ])

    gap = described_class.new(series).bearish.first

    expect(gap).to have_attributes(direction: :bearish, bottom: 104.0, top: 109.0)
  end

  it 'marks a gap invalidated once price trades all the way back through it' do
    series = crypto_series([
                             [100, 101, 99, 100],
                             [100, 106, 100, 105],
                             [105, 110, 105, 109],  # gap 101..105
                             [109, 110, 104, 105],  # tapped
                             [105, 106, 100, 101],  # traded through the bottom
                             [101, 103, 100, 102]
                           ])

    gap = described_class.new(series).bullish.first

    expect(gap.tapped?).to be(true)
    expect(gap.invalidated?).to be(true)
  end

  it 'ignores a gap too small to matter against ATR' do
    # Wide bars set a large ATR; the 0.01 gap between them is noise.
    series = crypto_series([
                             [100, 110, 90, 105],
                             [105, 120, 100, 115],
                             [115, 125, 110.01, 120],
                             [120, 126, 112, 121],
                             [121, 127, 113, 122]
                           ])

    expect(described_class.new(series).zones).to be_empty
  end

  describe '#candidates' do
    let(:series) do
      crypto_series([
                      [100, 101, 99, 100],
                      [100, 106, 100, 105],
                      [105, 110, 105, 109], # gap 101..105
                      [109, 115, 109, 114],
                      [114, 120, 114, 119],
                      [119, 121, 118, 120]
                    ])
    end

    it 'orders by distance from price, nearest first' do
      candidates = described_class.new(series).candidates(:bullish, 120.0)

      distances = candidates.map { |zone| zone.distance_from(120.0) }
      expect(distances).to eq(distances.sort)
      expect(candidates.first.top).to eq(118.0)
    end

    it 'excludes gaps price has already traded back through' do
      filled = described_class.new(series).zones.select(&:invalidated?)
      candidates = described_class.new(series).candidates(:bullish, 120.0)

      expect(candidates).not_to include(*filled) unless filled.empty?
      expect(candidates).to all(satisfy { |zone| !zone.invalidated? })
    end
  end
end
