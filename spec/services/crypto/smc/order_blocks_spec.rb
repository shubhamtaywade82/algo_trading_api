# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Crypto::Smc::OrderBlocks do
  # Pivot high at 110, pullback, then an impulse that closes through it. The
  # last down candle before that impulse is the bullish order block.
  let(:series) do
    crypto_series([
                    [100, 101, 99, 100],
                    [100, 103, 100, 102],
                    [102, 110, 101, 108],  # pivot high 110
                    [108, 108, 104, 105],
                    [105, 106, 100, 101],
                    [101, 102, 98, 99],    # pivot low 98
                    [99, 100, 96, 97],     # last bearish candle before the impulse
                    [97, 104, 97, 103],
                    [103, 113, 102, 112],  # BOS through 110
                    [112, 114, 110, 113],
                    [113, 115, 111, 114]
                  ])
  end

  let(:structure) { Crypto::Smc::Structure.new(series, strength: 2) }

  it 'marks the last opposing candle before the break as the order block' do
    zone = described_class.new(series, structure).bullish.first

    expect(zone).to have_attributes(direction: :bullish, kind: :order_block, bottom: 96.0, top: 100.0)
  end

  it 'leaves an untouched block fresh' do
    zone = described_class.new(series, structure).bullish.first

    expect(zone.fresh?).to be(true)
    expect(zone.tapped?).to be(false)
  end

  it 'marks the block tapped when price returns into it' do
    revisit = crypto_series(series.candles.map { |c| [c.open, c.high, c.low, c.close] } +
                            [[114, 115, 108, 109], [109, 110, 99, 100]])
    zone = described_class.new(revisit, Crypto::Smc::Structure.new(revisit, strength: 2)).bullish.first

    expect(zone.tapped?).to be(true)
    expect(zone.invalidated?).to be(false)
  end

  it 'invalidates the block when price closes below it' do
    broken = crypto_series(series.candles.map { |c| [c.open, c.high, c.low, c.close] } +
                           [[114, 115, 100, 101], [101, 102, 92, 93]])
    zone = described_class.new(broken, Crypto::Smc::Structure.new(broken, strength: 2)).bullish.first

    expect(zone.invalidated?).to be(true)
    expect(zone.valid?).to be(false)
  end

  it 'has no blocks when structure never broke' do
    flat = crypto_series(Array.new(20) { [100, 101, 99, 100] })

    expect(described_class.new(flat, Crypto::Smc::Structure.new(flat, strength: 2)).zones).to be_empty
  end
end
