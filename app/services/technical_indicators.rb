# frozen_string_literal: true

# app/services/technical_indicators.rb
# -----------------------------------------------------------------------------
# Centralised access point for *all* technical indicator calculations used by
# the AlgoTradingApi. Wraps the `technical-analysis` (Intrinio) gem and
# `ruby-technical-analysis` gem.
#
# Usage Example:
#   candles     = CandleSeries.for('NIFTY', frame: '5m')
#   indicators  = TechnicalIndicators.call(candles: candles, only: %i[rsi macd atr bb])
# -----------------------------------------------------------------------------

require 'technical_analysis'
require 'ruby_technical_analysis'

class TechnicalIndicators < ApplicationService
  INDICATORS = %i[rsi macd atr bb sma ema wma obv adx].freeze

  def initialize(candles:, only: nil, **opts)
    @candles = candles
    @only = only
    @opts = opts
  end

  def call
    raise ArgumentError, 'candles cannot be empty' if @candles.blank?

    prepare_series

    requested = Array(@only || INDICATORS).map(&:to_sym)

    requested.index_with do |name|
      raise "Unknown indicator: #{name}" unless INDICATORS.include?(name)

      send(:"calculate_#{name}", @opts[name] || {})
    end
  end

  private

  attr_reader :highs, :lows, :opens, :closes, :volumes

  def prepare_series
    @highs   = @candles.map { |c| c.high.to_f }
    @lows    = @candles.map { |c| c.low.to_f }
    @opens   = @candles.map { |c| c.open.to_f }
    @closes  = @candles.map { |c| c.close.to_f }
    @volumes = @candles.map { |c| c.volume.to_f }
  end

  def calculate_rsi(opts)
    length = opts.fetch(:length, 14)
    TechnicalAnalysis::Rsi.calculate(closes, period: length, price_key: :close).map(&:value)
  end

  def calculate_macd(opts)
    fast   = opts.fetch(:fast, 12)
    slow   = opts.fetch(:slow, 26)
    signal = opts.fetch(:signal, 9)
    TechnicalAnalysis::Macd.calculate(
      closes,
      fast_period: fast,
      slow_period: slow,
      signal_period: signal,
      price_key: :close
    ).map { |v| { macd: v.macd, signal: v.signal, hist: v.histogram } }
  end

  def calculate_atr(opts)
    length = opts.fetch(:length, 14)
    hlc = highs.zip(lows, closes).map { |h, l, c| { high: h, low: l, close: c } }
    TechnicalAnalysis::Atr.calculate(hlc, period: length).map(&:value)
  end

  def calculate_bb(opts)
    period = opts.fetch(:period, 20)
    std    = opts.fetch(:std_dev, 2)
    bb = RubyTechnicalAnalysis::BollingerBands.new(series: closes, period: period, std_dev: std).call
    { upper: bb[0], mid: bb[1], lower: bb[2] }
  end

  def calculate_sma(opts)
    len = opts.fetch(:length, 50)
    TechnicalAnalysis::Sma.calculate(closes, period: len, price_key: :close).map(&:value)
  end

  def calculate_ema(opts)
    len = opts.fetch(:length, 34)
    TechnicalAnalysis::Ema.calculate(closes, period: len, price_key: :close).map(&:value)
  end

  def calculate_wma(opts)
    len = opts.fetch(:length, 30)
    TechnicalAnalysis::Wma.calculate(closes, period: len, price_key: :close).map(&:value)
  end

  def calculate_obv(_opts)
    hlcv = closes.zip(volumes).map { |c, v| { close: c, volume: v } }
    TechnicalAnalysis::Obv.calculate(hlcv).map(&:value)
  end

  def calculate_adx(opts)
    len = opts.fetch(:length, 14)
    hlc = highs.zip(lows, closes).map { |h, l, c| { high: h, low: l, close: c } }
    TechnicalAnalysis::Adx.calculate(hlc, period: len).map(&:value)
  end
end
