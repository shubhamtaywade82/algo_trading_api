# frozen_string_literal: true

module Indicators
  # Simple slope helper for regime detection.
  # Returns average point-change per candle over the lookback window.
  class Slope
    def self.call(series:, lookback: 24)
      new(series: series, lookback: lookback).call
    end

    def initialize(series:, lookback:)
      @series = series
      @lookback = lookback.to_i
    end

    def call
      closes = @series.closes
      return 0.0 if closes.size < 2

      window = closes.last(@lookback + 1).map(&:to_f)
      return 0.0 if window.size < 2

      (window.last - window.first) / (window.size - 1).to_f
    end
  end
end

