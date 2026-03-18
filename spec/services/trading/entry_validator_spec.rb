# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trading::EntryValidator, type: :service do
  def build_candles(closes:, highs:, lows:)
    closes.each_with_index.map do |c, i|
      { open: c - 5, high: highs[i], low: lows[i], close: c, volume: 500 }
    end
  end

  describe '#call' do
    context 'CE direction' do
      context 'when last close is strictly above previous candle high (breakout)' do
        it 'returns valid: true' do
          candles = build_candles(
            closes: [21900.0, 21950.0, 22050.0],
            highs: [21920.0, 22000.0, 22100.0],
            lows: [21880.0, 21930.0, 22010.0]
          )
          result = described_class.call(direction: 'CE', candles: candles)
          expect(result.valid).to be true
          expect(result.reason).to eq('Bullish breakout confirmed')
        end
      end

      context 'when last close equals previous candle high (strict > required)' do
        it 'returns valid: false' do
          candles = build_candles(
            closes: [21900.0, 21950.0, 22000.0],
            highs: [21920.0, 22000.0, 22050.0],
            lows: [21880.0, 21930.0, 21980.0]
          )
          result = described_class.call(direction: 'CE', candles: candles)
          expect(result.valid).to be false
          expect(result.reason).to include('No breakout')
        end
      end

      context 'when last close is below previous candle high' do
        it 'returns valid: false' do
          candles = build_candles(
            closes: [21900.0, 21950.0, 21980.0],
            highs: [21920.0, 22000.0, 22050.0],
            lows: [21880.0, 21930.0, 21960.0]
          )
          result = described_class.call(direction: 'CE', candles: candles)
          expect(result.valid).to be false
        end
      end
    end

    context 'PE direction' do
      context 'when last close is strictly below previous candle low (breakdown)' do
        it 'returns valid: true' do
          candles = build_candles(
            closes: [22100.0, 22050.0, 21900.0],
            highs: [22130.0, 22080.0, 21950.0],
            lows: [22080.0, 21950.0, 21880.0]
          )
          result = described_class.call(direction: 'PE', candles: candles)
          expect(result.valid).to be true
          expect(result.reason).to eq('Bearish breakdown confirmed')
        end
      end

      context 'when last close equals previous candle low (strict < required)' do
        it 'returns valid: false' do
          candles = build_candles(
            closes: [22100.0, 22050.0, 21950.0],
            highs: [22130.0, 22080.0, 22000.0],
            lows: [22080.0, 21950.0, 21930.0]
          )
          result = described_class.call(direction: 'PE', candles: candles)
          expect(result.valid).to be false
          expect(result.reason).to include('No breakdown')
        end
      end

      context 'when last close is above previous candle low' do
        it 'returns valid: false' do
          candles = build_candles(
            closes: [22100.0, 22050.0, 22000.0],
            highs: [22130.0, 22080.0, 22030.0],
            lows: [22080.0, 21950.0, 21980.0]
          )
          result = described_class.call(direction: 'PE', candles: candles)
          expect(result.valid).to be false
        end
      end
    end

    context 'when fewer than 3 candles provided' do
      it 'returns valid: false with insufficient candles message' do
        candles = [
          { open: 22000.0, high: 22100.0, low: 21900.0, close: 22050.0, volume: 500 },
          { open: 22050.0, high: 22150.0, low: 22000.0, close: 22100.0, volume: 500 }
        ]
        result = described_class.call(direction: 'CE', candles: candles)
        expect(result.valid).to be false
        expect(result.reason).to include('Insufficient candles')
      end
    end

    context 'when direction is unknown' do
      it 'returns valid: false with unknown direction message' do
        candles = build_candles(
          closes: [21900.0, 21950.0, 22050.0],
          highs: [21920.0, 22000.0, 22100.0],
          lows: [21880.0, 21930.0, 22010.0]
        )
        result = described_class.call(direction: 'UNKNOWN', candles: candles)
        expect(result.valid).to be false
        expect(result.reason).to include('Unknown direction')
      end
    end

    context 'direction is case-insensitive' do
      it 'handles lowercase ce' do
        candles = build_candles(
          closes: [21900.0, 21950.0, 22050.0],
          highs: [21920.0, 22000.0, 22100.0],
          lows: [21880.0, 21930.0, 22010.0]
        )
        result = described_class.call(direction: 'ce', candles: candles)
        expect(result.valid).to be true
      end
    end
  end
end

