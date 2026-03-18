# frozen_string_literal: true

module Trading
  # Determines whether market conditions allow trading.
  # Checks IV rank bounds and candle range adequacy, then detects trend.
  class RegimeScorer < ApplicationService
    Result = Struct.new(:state, :trend, :reason, keyword_init: true)

    LOW_IV_THRESHOLD  = 20.0
    HIGH_IV_THRESHOLD = 80.0
    MIN_RANGE_PCT     = 0.2   # minimum avg 5-candle range as % of spot

    def initialize(spot:, candles:, iv_rank:)
      @spot    = spot.to_f
      @candles = candles
      @iv_rank = iv_rank.to_f
    end

    def call
      return no_trade("IV rank too low (#{@iv_rank.round(1)}): no premium") if @iv_rank < LOW_IV_THRESHOLD
      return no_trade("IV rank extreme (#{@iv_rank.round(1)}): event risk") if @iv_rank > HIGH_IV_THRESHOLD
      return no_trade('Insufficient candles for regime check') if @candles.size < 5

      avg_range_pct = average_range_pct
      return no_trade("Market too quiet (avg range #{avg_range_pct.round(3)}%)") if avg_range_pct < MIN_RANGE_PCT

      trend = detect_trend
      Result.new(state: :tradeable, trend: trend, reason: nil)
    end

    private

    def average_range_pct
      last5  = @candles.last(5)
      ranges = last5.map { |c| candle_float(c, :high) - candle_float(c, :low) }
      (ranges.sum / ranges.size.to_f) / @spot * 100.0
    end

    def detect_trend
      closes = @candles.map { |c| candle_float(c, :close) }
      ema20  = compute_ema(closes, 20)
      return :range if ema20.nil?

      last_close = closes.last
      return :bullish if last_close > ema20
      return :bearish if last_close < ema20

      :range
    end

    def compute_ema(closes, period)
      return nil if closes.size < period

      multiplier = 2.0 / (period + 1)
      ema = closes.first(period).sum / period.to_f
      closes[period..].each { |c| ema = (c - ema) * multiplier + ema }
      ema
    end

    def candle_float(candle, key)
      candle[key].to_f
    end

    def no_trade(reason)
      Result.new(state: :no_trade, trend: nil, reason: reason)
    end
  end
end

