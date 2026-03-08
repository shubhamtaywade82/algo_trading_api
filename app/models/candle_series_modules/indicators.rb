# frozen_string_literal: true

module CandleSeriesModules
  # Technical indicators extraction for CandleSeries
  module Indicators
    def atr(period = 14)
      val = TechnicalAnalysis::Atr.calculate(hlc, period: period).first.atr
      { atr: val }
    end

    def rsi(period = 14)
      val = RubyTechnicalAnalysis::RelativeStrengthIndex.new(series: closes, period: period).call
      { rsi: val }
    end

    def moving_average(period = 20)
      ma = RubyTechnicalAnalysis::MovingAverages.new(series: closes, period: period)
      { sma: ma.sma, ema: ma.ema, wma: ma.wma }
    end

    def sma(period = 20) = { sma: RubyTechnicalAnalysis::MovingAverages.new(series: closes, period: period).sma }
    def ema(period = 20) = { ema: RubyTechnicalAnalysis::MovingAverages.new(series: closes, period: period).ema }

    def macd(fast_period = 12, slow_period = 26, signal_period = 9)
      min_length = slow_period + signal_period
      return empty_macd if closes.size < min_length

      series = closes.map(&:to_f)
      line, signal, hist = RubyTechnicalAnalysis::Macd.new(
        series: series,
        fast_period: fast_period,
        slow_period: slow_period,
        signal_period: signal_period
      ).call

      { macd: line, signal: signal, hist: hist }
    rescue StandardError
      empty_macd
    end

    def rate_of_change(period = 5)
      return { roc: nil } if closes.size < period + 1

      roc_series = closes.map.with_index do |price, idx|
        if idx < period
          nil
        else
          prev = closes[idx - period]
          ((price - prev) / prev.to_f) * 100.0
        end
      end

      { roc: roc_series }
    end

    private

    def empty_macd
      { macd: nil, signal: nil, hist: nil }
    end
  end
end
