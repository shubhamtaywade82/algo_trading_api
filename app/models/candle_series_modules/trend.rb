# frozen_string_literal: true

module CandleSeriesModules
  # Trend analysis utilities for CandleSeries
  module Trend
    def supertrend_signal
      indicator   = ::Indicators::AdaptiveSupertrend.new(series: self)
      trend_line  = indicator.call
      latest_trend = trend_line.last
      return nil unless latest_trend

      latest_close = closes.last

      return :bullish if latest_close > latest_trend

      :bearish if latest_close < latest_trend
    end

    def bollinger_bands(period: 20)
      return nil if candles.size < period

      bb = RubyTechnicalAnalysis::BollingerBands.new(series: closes, period: period).call
      { upper: bb[0], lower: bb[1], middle: bb[2] }
    end

    def donchian_channel(period: 20)
      return nil if candles.size < period

      dc = candles.map { |c| { date_time: c.timestamp, value: c.close } }
      { donchian: TechnicalAnalysis::Dc.calculate(dc, period: period) }
    end
  end
end
