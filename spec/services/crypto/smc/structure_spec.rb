# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Crypto::Smc::Structure do
  # Up-leg to a pivot high at 110, pullback to a pivot low, then a close back
  # above 110. The break is bullish and, with no prior trend, is a BOS.
  let(:bullish_break) do
    crypto_series([
                    [100, 101, 99, 100],
                    [100, 103, 100, 102],
                    [102, 110, 101, 108],  # pivot high 110 @ index 2
                    [108, 108, 104, 105],
                    [105, 106, 100, 101],
                    [101, 102, 98, 99],    # pivot low 98 @ index 5
                    [99, 104, 99, 103],
                    [103, 108, 102, 107],
                    [107, 113, 106, 112],  # closes above 110 -> bullish break
                    [112, 114, 110, 113],
                    [113, 115, 111, 114]
                  ])
  end

  it 'reports a bullish BOS when the first break has no trend to contradict' do
    events = described_class.new(bullish_break, strength: 2).events

    expect(events.size).to eq(1)
    expect(events.first).to have_attributes(type: :bos, direction: :bullish, level: 110.0)
  end

  it 'sets the trend from the last event' do
    expect(described_class.new(bullish_break, strength: 2).trend).to eq(:bullish)
  end

  it 'requires a close beyond the level, not merely a wick' do
    # Same path, but the breaking bar wicks to 113 and closes back at 109.
    wick_only = crypto_series([
                                [100, 101, 99, 100],
                                [100, 103, 100, 102],
                                [102, 110, 101, 108],
                                [108, 108, 104, 105],
                                [105, 106, 100, 101],
                                [101, 102, 98, 99],
                                [99, 104, 99, 103],
                                [103, 108, 102, 107],
                                [107, 113, 106, 109], # wick through 110, close under
                                [109, 110, 107, 108],
                                [108, 109, 106, 107]
                              ])

    expect(described_class.new(wick_only, strength: 2).events).to be_empty
  end

  it 'calls the counter-trend break a CHoCH' do
    # Bullish BOS first, then a close below the swing low that follows it.
    series = crypto_series([
                             [100, 101, 99, 100],
                             [100, 103, 100, 102],
                             [102, 110, 101, 108],
                             [108, 108, 104, 105],
                             [105, 106, 100, 101],
                             [101, 102, 98, 99],
                             [99, 104, 99, 103],
                             [103, 108, 102, 107],
                             [107, 113, 106, 112],  # BOS bullish through 110
                             [112, 116, 111, 115],
                             [115, 118, 112, 113],  # pivot high 118
                             [113, 114, 108, 109],
                             [109, 110, 105, 106],  # pivot low 105
                             [106, 111, 105, 110],
                             [110, 112, 108, 111],
                             [111, 112, 103, 104],  # closes below 105 -> CHoCH bearish
                             [104, 105, 100, 101],
                             [101, 103, 99, 100]
                           ])

    events = described_class.new(series, strength: 2).events

    expect(events.map { |e| [e.type, e.direction] }).to include(%i[bos bullish], %i[choch bearish])
    expect(events.last.direction).to eq(:bearish)
  end

  describe '#recent_event' do
    it 'ignores an event older than the lookback' do
      structure = described_class.new(bullish_break, strength: 2)

      expect(structure.recent_event(direction: :bullish, lookback: 10)).to be_present
      expect(structure.recent_event(direction: :bullish, lookback: 1)).to be_nil
    end
  end

  describe '#dealing_range' do
    it 'spans the recent swing high and low' do
      range = described_class.new(bullish_break, strength: 2).dealing_range

      expect(range[:high]).to eq(110.0)
      expect(range[:low]).to eq(98.0)
    end
  end

  it 'returns no events when the series is too short to hold a pivot' do
    expect(described_class.new(crypto_series([[100, 101, 99, 100]]), strength: 2).events).to be_empty
  end
end
