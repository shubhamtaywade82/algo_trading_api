# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Crypto::SetupDetector do
  # The detector's job is to decide, so these specs feed it a controlled view
  # of each timeframe and assert on the decision. The detectors that build
  # those views have their own specs.
  def build_report(bias:, price: 100.0, atr: 1.0, poi: nil, sweep: nil, trigger: nil,
                   favourable: true, ote: true, displacement: true, confirmation: true,
                   imbalance: true, target_above: nil, target_below: nil, size: 60)
    bars = Array.new(size) { [price, price + 1, price - 2, price] }
    series = crypto_series(bars)

    instance_double(
      Crypto::Smc::TimeframeReport,
      bias: bias, price: price, atr: atr, series: series,
      structure: instance_double(
        Crypto::Smc::Structure,
        recent_event: trigger,
        next_liquidity_above: target_above,
        next_liquidity_below: target_below
      ),
      premium_discount: instance_double(
        Crypto::Smc::PremiumDiscount,
        favourable?: favourable, in_ote?: ote, zone: :discount
      ),
      active_poi: poi,
      liquidity: instance_double(
        Crypto::Smc::Liquidity,
        recent_sweep: sweep, target_above: target_above, target_below: target_below
      ),
      price_action: instance_double(
        Crypto::Smc::PriceAction,
        displacement?: displacement, engulfing?: confirmation, rejection?: confirmation
      ),
      fair_value_gaps: instance_double(
        Crypto::Smc::FairValueGaps,
        candidates: imbalance ? [bullish_poi] : []
      )
    )
  end

  let(:bullish_poi) do
    Crypto::Smc::Zone.new(kind: :order_block, direction: :bullish, top: 99.0, bottom: 97.5,
                          index: 55, time: Time.current)
  end

  let(:bullish_sweep) do
    Crypto::Smc::Liquidity::Sweep.new(direction: :bullish, level: 97.8, index: 55,
                                      time: Time.current, penetration: 0.4)
  end

  let(:bullish_trigger) do
    Crypto::Smc::Structure::Event.new(type: :bos, direction: :bullish, level: 99.5,
                                      index: 55, time: Time.current)
  end

  # A complete, textbook long: every timeframe aligned, POI tapped, liquidity
  # swept, 5m broken structure upward, targets in place.
  def long_reports(overrides = {})
    defaults = {
      '1d' => build_report(bias: :bullish),
      '4h' => build_report(bias: :bullish),
      '1h' => build_report(bias: :bullish, trigger: bullish_trigger, target_above: 115.0),
      '15m' => build_report(bias: :bullish, atr: 2.0, poi: bullish_poi, sweep: bullish_sweep,
                            target_above: 108.0),
      '5m' => build_report(bias: :bullish, trigger: bullish_trigger, target_above: 108.0)
    }
    defaults.merge(overrides)
  end

  describe 'the happy path' do
    subject(:setup) { described_class.call(symbol: 'SOLUSDT', reports: long_reports) }

    it 'produces a long setup' do
      expect(setup).to be_a(Crypto::Setup)
      expect(setup).to be_long
      expect(setup.symbol).to eq('SOLUSDT')
    end

    it 'places the stop below the deepest structure plus a buffer' do
      # anchors: POI bottom 97.5, sweep 97.8, 5m swing low 98 -> 97.5 - (1.0 * 0.3)
      expect(setup.stop).to be_within(0.001).of(97.2)
      expect(setup.risk).to be_within(0.001).of(2.8)
    end

    it 'targets resting liquidity, ordered outward' do
      expect(setup.target1).to eq(108.0)
      expect(setup.target2).to eq(115.0)
      expect(setup.target2).to be > setup.target1
    end

    it 'reports the reward:risk to the first target' do
      expect(setup.risk_reward).to eq(2.86)
    end

    it 'scores every confluence it found' do
      expect(setup.score).to eq(100.0)
      expect(setup.grade).to eq('A+')
      expect(setup.confluences.pluck(:key)).to include(:m5_trigger, :m15_poi, :m15_sweep)
    end
  end

  describe 'hard gates' do
    it 'refuses without a 5m trigger, however good the context' do
      reports = long_reports('5m' => build_report(bias: :bullish, trigger: nil, target_above: 108.0))

      expect(described_class.call(symbol: 'SOLUSDT', reports: reports)).to be_nil
    end

    it 'refuses when both higher timeframes oppose the trade' do
      reports = long_reports(
        '1d' => build_report(bias: :bearish),
        '4h' => build_report(bias: :bearish)
      )

      expect(described_class.call(symbol: 'SOLUSDT', reports: reports)).to be_nil
    end

    it 'refuses when the timeframes cannot agree on a direction' do
      reports = long_reports(
        '1d' => build_report(bias: :bullish),
        '4h' => build_report(bias: :bearish),
        '1h' => build_report(bias: :neutral, target_above: 115.0)
      )

      expect(described_class.call(symbol: 'SOLUSDT', reports: reports)).to be_nil
    end

    it 'refuses when the score falls below the threshold' do
      thin = long_reports(
        '15m' => build_report(bias: :bullish, atr: 2.0, poi: nil, sweep: nil, favourable: false,
                              ote: false, imbalance: false, target_above: 108.0),
        '1h' => build_report(bias: :neutral, favourable: false, ote: false, target_above: 115.0)
      )

      expect(described_class.call(symbol: 'SOLUSDT', reports: thin)).to be_nil
    end

    it 'refuses when the reward:risk does not clear the minimum' do
      # Target only just beyond entry, so R:R lands under 1.8.
      reports = long_reports(
        '15m' => build_report(bias: :bullish, atr: 2.0, poi: bullish_poi, sweep: bullish_sweep,
                              target_above: 101.0),
        '1h' => build_report(bias: :bullish, target_above: 101.5)
      )

      expect(described_class.call(symbol: 'SOLUSDT', reports: reports, min_risk_reward: 5.0)).to be_nil
    end

    it 'refuses when the stop is wider than the 15m ATR allows' do
      # A 15m ATR of 0.5 makes the ceiling 1.25, well under the 2.8 stop.
      reports = long_reports(
        '15m' => build_report(bias: :bullish, atr: 0.5, poi: bullish_poi, sweep: bullish_sweep,
                              target_above: 108.0)
      )

      expect(described_class.call(symbol: 'SOLUSDT', reports: reports)).to be_nil
    end

    it 'refuses when a timeframe is missing' do
      expect(described_class.call(symbol: 'SOLUSDT', reports: long_reports.except('4h'))).to be_nil
    end

    it 'refuses when a timeframe has too little history to read' do
      reports = long_reports('1d' => build_report(bias: :bullish, size: 10))

      expect(described_class.call(symbol: 'SOLUSDT', reports: reports)).to be_nil
    end
  end

  describe 'shorts' do
    let(:bearish_poi) do
      Crypto::Smc::Zone.new(kind: :order_block, direction: :bearish, top: 102.5, bottom: 101.0,
                            index: 55, time: Time.current)
    end

    let(:bearish_trigger) do
      Crypto::Smc::Structure::Event.new(type: :choch, direction: :bearish, level: 100.5,
                                        index: 55, time: Time.current)
    end

    it 'mirrors the long logic' do
      reports = {
        '1d' => build_report(bias: :bearish),
        '4h' => build_report(bias: :bearish),
        '1h' => build_report(bias: :bearish, target_below: 85.0),
        '15m' => build_report(bias: :bearish, atr: 2.0, poi: bearish_poi, target_below: 92.0),
        '5m' => build_report(bias: :bearish, trigger: bearish_trigger, target_below: 92.0)
      }

      setup = described_class.call(symbol: 'ETHUSDT', reports: reports)

      expect(setup).to be_short
      expect(setup.stop).to be > setup.entry
      expect(setup.target1).to be < setup.entry
      expect(setup.target2).to be < setup.target1
    end
  end
end
