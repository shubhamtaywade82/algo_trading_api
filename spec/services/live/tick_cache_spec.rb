# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::TickCache do
  before { described_class.clear! }

  after { described_class.clear! }

  it 'stores and reads a tick' do
    described_class.put('NSE_FNO', '49081', ltp: 123.45, kind: :quote)

    expect(described_class.ltp('NSE_FNO', '49081')).to eq(123.45)
  end

  # Callers pass security ids as both Integer and String; they must collide.
  it 'normalises integer and string security ids to one entry' do
    described_class.put('NSE_FNO', 49_081, ltp: 100.0)

    expect(described_class.ltp('NSE_FNO', '49081')).to eq(100.0)
    expect(described_class.size).to eq(1)
  end

  it 'keeps segments separate' do
    described_class.put('NSE_EQ', '1', ltp: 10.0)
    described_class.put('BSE_EQ', '1', ltp: 20.0)

    expect(described_class.ltp('NSE_EQ', '1')).to eq(10.0)
    expect(described_class.ltp('BSE_EQ', '1')).to eq(20.0)
  end

  # A stale price is worse than none: the caller should fall back to REST.
  it 'treats a tick older than the ttl as absent' do
    described_class.put('NSE_FNO', '49081', ltp: 123.45)

    travel_to(31.seconds.from_now) do
      expect(described_class.get('NSE_FNO', '49081')).to be_nil
      expect(described_class.ltp('NSE_FNO', '49081')).to be_nil
    end
  end

  it 'honours an explicit ttl' do
    described_class.put('NSE_FNO', '49081', ltp: 123.45)

    travel_to(10.seconds.from_now) do
      expect(described_class.ltp('NSE_FNO', '49081', ttl: 5)).to be_nil
      expect(described_class.ltp('NSE_FNO', '49081', ttl: 60)).to eq(123.45)
    end
  end

  it 'returns nil for an unknown instrument' do
    expect(described_class.ltp('NSE_FNO', 'nope')).to be_nil
  end

  it 'deletes and clears' do
    described_class.put('NSE_FNO', '1', ltp: 1.0)
    described_class.delete('NSE_FNO', '1')

    expect(described_class.size).to eq(0)
  end

  it 'excludes stale entries from a snapshot' do
    described_class.put('NSE_FNO', 'fresh', ltp: 1.0)

    travel_to(31.seconds.from_now) do
      described_class.put('NSE_FNO', 'newer', ltp: 2.0)

      expect(described_class.snapshot.keys).to contain_exactly('NSE_FNO:newer')
    end
  end
end
