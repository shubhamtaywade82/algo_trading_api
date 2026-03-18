# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trading::DirectionResolver, type: :service do
  let(:spot) { 22100.0 }

  # Build candles for VWAP calculation
  def build_candles(close:, volume: 1000)
    Array.new(5) { { open: close - 5, high: close + 10, low: close - 10, close: close, volume: volume } }
  end

  # Build option chain in DhanHQ nested format:
  #   { oc: { "22000.000000" => { "ce" => { "oi" => N }, "pe" => { "oi" => N } } }, last_price: spot }
  def build_chain(ce_oi:, pe_oi:, spot: 22000.0)
    {
      last_price: spot,
      oc: {
        '22000.000000' => {
          'ce' => { 'oi' => ce_oi, 'implied_volatility' => 0.15 },
          'pe' => { 'oi' => pe_oi, 'implied_volatility' => 0.18 }
        }
      }
    }
  end

  describe '#call' do
    context 'when both price and OI biases are bullish' do
      it 'returns CE direction' do
        candles = build_candles(close: 21900.0) # spot > vwap => bullish price
        chain = build_chain(ce_oi: 100_000, pe_oi: 500_000) # PE > CE OI => bullish OI

        result = described_class.call(spot: spot, candles: candles, option_chain: chain)
        expect(result.direction).to eq('CE')
        expect(result.price_bias).to eq(:bullish)
        expect(result.oi_bias).to eq(:bullish)
      end
    end

    context 'when both price and OI biases are bearish' do
      it 'returns PE direction' do
        candles = build_candles(close: 22300.0) # spot < vwap => bearish price
        chain = build_chain(ce_oi: 500_000, pe_oi: 100_000) # CE > PE OI => bearish OI

        result = described_class.call(spot: spot, candles: candles, option_chain: chain)
        expect(result.direction).to eq('PE')
        expect(result.price_bias).to eq(:bearish)
        expect(result.oi_bias).to eq(:bearish)
      end
    end

    context 'when price is bullish but OI is bearish (no confirmation)' do
      it 'returns nil direction' do
        candles = build_candles(close: 21900.0) # bullish price
        chain = build_chain(ce_oi: 500_000, pe_oi: 100_000) # bearish OI

        result = described_class.call(spot: spot, candles: candles, option_chain: chain)
        expect(result.direction).to be_nil
        expect(result.reason).to include('No confirmation')
      end
    end

    context 'when price is bearish but OI is bullish (no confirmation)' do
      it 'returns nil direction' do
        candles = build_candles(close: 22300.0) # bearish price
        chain = build_chain(ce_oi: 100_000, pe_oi: 500_000) # bullish OI

        result = described_class.call(spot: spot, candles: candles, option_chain: chain)
        expect(result.direction).to be_nil
      end
    end

    context 'when all candles have zero volume' do
      it 'falls back to simple average for VWAP' do
        candles = build_candles(close: 21900.0, volume: 0)
        chain = build_chain(ce_oi: 100_000, pe_oi: 500_000)

        result = described_class.call(spot: spot, candles: candles, option_chain: chain)
        expect(result.price_bias).to eq(:bullish)
      end
    end

    context 'when option chain is empty or OC has no strikes' do
      it 'returns neutral OI bias and no direction' do
        candles = build_candles(close: 21900.0)
        chain = { last_price: 22000.0, oc: {} }

        result = described_class.call(spot: spot, candles: candles, option_chain: chain)
        expect(result.oi_bias).to eq(:neutral)
        expect(result.direction).to be_nil
      end
    end

    context 'when CE OI equals PE OI' do
      it 'returns neutral OI bias' do
        candles = build_candles(close: 21900.0)
        chain = build_chain(ce_oi: 200_000, pe_oi: 200_000)

        result = described_class.call(spot: spot, candles: candles, option_chain: chain)
        expect(result.oi_bias).to eq(:neutral)
        expect(result.direction).to be_nil
      end
    end
  end
end

