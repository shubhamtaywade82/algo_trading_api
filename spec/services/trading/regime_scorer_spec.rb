# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trading::RegimeScorer, type: :service do
  # Build synthetic candles with controllable high/low/close values
  def build_candles(count, high: 22100.0, low: 21900.0, close: 22000.0)
    Array.new(count) { { open: close - 10, high: high, low: low, close: close, volume: 1000 } }
  end

  # Build trending candles: ascending closes for bullish EMA bias
  def build_trending_candles(count, base: 22000.0, step: 10.0, high_offset: 100.0, low_offset: 100.0)
    Array.new(count).each_with_index.map do |_, i|
      c = base + (i * step)
      { open: c - 5, high: c + high_offset, low: c - low_offset, close: c, volume: 1000 }
    end
  end

  let(:spot) { 22000.0 }
  let(:healthy_candles) { build_candles(20, high: 22200.0, low: 21800.0, close: 22000.0) }

  describe '#call' do
    context 'when IV rank is below minimum threshold (< 20)' do
      it 'returns no_trade with low IV message' do
        result = described_class.call(spot: spot, candles: healthy_candles, iv_rank: 19.9)
        expect(result.state).to eq(:no_trade)
        expect(result.reason).to include('IV rank too low')
      end
    end

    context 'when IV rank is at boundary (== 20.0)' do
      it 'returns tradeable when candles and range are sufficient' do
        result = described_class.call(spot: spot, candles: healthy_candles, iv_rank: 20.0)
        expect(result.state).to eq(:tradeable)
      end
    end

    context 'when IV rank is above maximum threshold (> 80)' do
      it 'returns no_trade with extreme IV message' do
        result = described_class.call(spot: spot, candles: healthy_candles, iv_rank: 80.1)
        expect(result.state).to eq(:no_trade)
        expect(result.reason).to include('IV rank extreme')
      end
    end

    context 'when IV rank is exactly at upper boundary (== 80.0)' do
      it 'returns tradeable' do
        result = described_class.call(spot: spot, candles: healthy_candles, iv_rank: 80.0)
        expect(result.state).to eq(:tradeable)
      end
    end

    context 'when fewer than 5 candles are provided' do
      it 'returns no_trade with insufficient candles message' do
        result = described_class.call(spot: spot, candles: build_candles(4), iv_rank: 40.0)
        expect(result.state).to eq(:no_trade)
        expect(result.reason).to include('Insufficient candles')
      end
    end

    context 'when average range is below minimum (< 0.2% of spot)' do
      it 'returns no_trade with market too quiet message' do
        # Range of 10 points on 22000 spot = 0.045% — below 0.2% threshold
        tight_candles = build_candles(10, high: 22005.0, low: 21995.0, close: 22000.0)
        result = described_class.call(spot: spot, candles: tight_candles, iv_rank: 40.0)
        expect(result.state).to eq(:no_trade)
        expect(result.reason).to include('Market too quiet')
      end
    end

    context 'when all conditions are healthy' do
      it 'returns tradeable state' do
        result = described_class.call(spot: spot, candles: healthy_candles, iv_rank: 40.0)
        expect(result.state).to eq(:tradeable)
        expect(result.reason).to be_nil
      end
    end

    context 'trend detection' do
      it 'detects bullish trend when close is above EMA20' do
        # Build 25 candles with ascending closes so last close exceeds EMA20
        candles = build_trending_candles(25, base: 21000.0, step: 50.0, high_offset: 200.0, low_offset: 200.0)
        result = described_class.call(spot: candles.last[:close], candles: candles, iv_rank: 40.0)
        expect(result.state).to eq(:tradeable)
        expect(result.trend).to eq(:bullish)
      end

      it 'detects bearish trend when close is below EMA20' do
        # Build 25 descending candles
        candles = build_trending_candles(25, base: 23000.0, step: -50.0, high_offset: 200.0, low_offset: 200.0)
        result = described_class.call(spot: candles.last[:close], candles: candles, iv_rank: 40.0)
        expect(result.state).to eq(:tradeable)
        expect(result.trend).to eq(:bearish)
      end

      it 'falls back to :range when fewer than 20 candles (no EMA20)' do
        # Only 10 candles — can't compute EMA20
        candles = build_candles(10, high: 22300.0, low: 21700.0, close: 22000.0)
        result = described_class.call(spot: spot, candles: candles, iv_rank: 40.0)
        expect(result.state).to eq(:tradeable)
        expect(result.trend).to eq(:range)
      end
    end
  end
end

