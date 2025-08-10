# frozen_string_literal: true

# app/services/technical_indicators.rb
# -----------------------------------------------------------------------------
# Centralised access point for *all* technical indicator calculations used by
# the AlgoTradingApi.  Wraps the `technical-analysis` (Intrinio) gem for the
# heavier‑weight TA functions and `ruby-technical-analysis` for a handful of
# light‑weight / statistical helpers, exposing a single, ergonomic interface.
#
# Usage Example (inside any service / strategy):
#   candles     = CandleSeries.for('NIFTY', frame: '5m')
#   indicators  = TechnicalIndicators.call(candles: candles, only: %i[rsi macd atr bb])
#
#   rsi_14      = indicators[:rsi]      # => Array<Float>
#   last_macd   = indicators[:macd].last
#   upper_bb    = indicators.dig(:bb, :upper).last
# -----------------------------------------------------------------------------

require 'technical_analysis'          # intrinio/technical-analysis
require 'ruby_technical_analysis'     # johnnypaper/ruby-technical-analysis

module TechnicalIndicators
  extend self

  # Public API ---------------------------------------------------------------
  # @param candles [Array<Candle>|ActiveRecord::Relation]
  #        Each candle responds to :high, :low, :open, :close, :volume
  # @param only    [Array<Symbol>, nil]
  #        Optionally restrict calculation to this subset (default = ALL).
  # @param opts    [Hash] Per‑indicator overrides, e.g. { rsi: { length: 21 } }
  # @return [Hash] { indicator_name => result }
  # -------------------------------------------------------------------------
  def call(candles:, only: nil, **opts)
    raise ArgumentError, 'candles cannot be empty' if candles.blank?

    prepare_series(candles)

    requested = Array(only || INDICATOR_MAP.keys).map(&:to_sym)

    requested.index_with do |name|
      INDICATOR_MAP.fetch(name).call(opts[name] || {})
    end
  end

  # -------------------------------------------------------------------------
  private

  # Convenience accessors built from the candle array
  attr_reader :highs, :lows, :opens, :closes, :volumes

  def prepare_series(candles)
    @highs   = candles.map { |c| c.high.to_f }
    @lows    = candles.map { |c| c.low.to_f }
    @opens   = candles.map { |c| c.open.to_f }
    @closes  = candles.map { |c| c.close.to_f }
    @volumes = candles.map { |c| c.volume.to_f }
  end

  # -------------------------------------------------------------------------
  # Indicator Implementations ------------------------------------------------
  # Each lambda receives the **options** hash passed for that indicator and
  # *must* return either an Array (vector) or a Struct/Hash with arrays.
  # -------------------------------------------------------------------------
  INDICATOR_MAP = {
    # ——————————————————— Momentum / Oscillators ————————————————————
    rsi: lambda do |o|
      length = o.fetch(:length, 14)
      TechnicalAnalysis::Rsi.calculate(closes, period: length, price_key: :close)
                            .map(&:value)
    end,

    macd: lambda do |o|
      fast   = o.fetch(:fast, 12)
      slow   = o.fetch(:slow, 26)
      signal = o.fetch(:signal, 9)
      TechnicalAnalysis::Macd.calculate(closes,
                                        fast_period: fast,
                                        slow_period: slow,
                                        signal_period: signal,
                                        price_key: :close)
                             .map { |v| { macd: v.macd, signal: v.signal, hist: v.histogram } }
    end,

    atr: lambda do |o|
      length = o.fetch(:length, 14)
      # The TA gem expects an array of hashes with :high, :low, :close keys
      hlc = highs.zip(lows, closes).map { |h, l, c| { high: h, low: l, close: c } }
      TechnicalAnalysis::Atr.calculate(hlc, period: length)
                            .map(&:value)
    end,

    # ——————————————————— Volatility Bands ————————————————————————
    bb: lambda do |o|
      period = o.fetch(:period, 20)
      std    = o.fetch(:std_dev, 2)
      bb = RubyTechnicalAnalysis::BollingerBands.new(series: closes,
                                                     period: period,
                                                     std_dev: std).call
      { upper: bb[0], mid: bb[1], lower: bb[2] }
    end,

    # ——————————————————— Moving Averages ————————————————————————
    sma: lambda do |o|
      len = o.fetch(:length, 50)
      TechnicalAnalysis::Sma.calculate(closes, period: len, price_key: :close)
                            .map(&:value)
    end,

    ema: lambda do |o|
      len = o.fetch(:length, 34)
      TechnicalAnalysis::Ema.calculate(closes, period: len, price_key: :close)
                            .map(&:value)
    end,

    wma: lambda do |o|
      len = o.fetch(:length, 30)
      TechnicalAnalysis::Wma.calculate(closes, period: len, price_key: :close)
                            .map(&:value)
    end,

    # ——————————————————— Volume‑based ————————————————————————
    obv: lambda do |_o|
      hlcv = closes.zip(volumes).map { |c, v| { close: c, volume: v } }
      TechnicalAnalysis::Obv.calculate(hlcv).map(&:value)
    end,

    adx: lambda do |o|
      len = o.fetch(:length, 14)
      hlc = highs.zip(lows, closes).map { |h, l, c| { high: h, low: l, close: c } }
      TechnicalAnalysis::Adx.calculate(hlc, period: len).map(&:value)
    end
  }.freeze
end
