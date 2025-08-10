# frozen_string_literal: true

module Indicators
  class Supertrend
    # period      → ATR look-back
    # multiplier  → ATR multiplier (default 3)
    def initialize(series:, period: 10, multiplier: 2)
      @series     = series
      @period     = period
      @multiplier = multiplier
    end

    # Returns an Array<Float|nil> aligned with the candle index
    def call
      highs  = @series.highs
      lows   = @series.lows
      closes = @series.closes

      # --- 1. ATR (simple version) ------------------------------------------
      trs = highs.zip(lows, closes.each_cons(2).map(&:first).unshift(nil)).map do |h, l, prev_close|
        next nil unless prev_close

        [(h - l), (h - prev_close).abs, (l - prev_close).abs].max
      end
      atr = Array.new(closes.size)
      trs.each_with_index do |tr, i|
        if i == @period
          atr[i] = trs[1..@period].compact.sum / @period.to_f
        elsif i > @period
          atr[i] = ((atr[i - 1] * (@period - 1)) + tr) / @period.to_f
        end
      end

      # --- 2. Bands ----------------------------------------------------------
      upperband = Array.new(closes.size)
      lowerband = Array.new(closes.size)
      closes.each_index do |i|
        next if atr[i].nil?

        mid = (highs[i] + lows[i]) / 2.0
        upperband[i] = mid + (@multiplier * atr[i])
        lowerband[i] = mid - (@multiplier * atr[i])
      end

      # --- 3. Supertrend line ----------------------------------------------
      st = Array.new(closes.size)
      (0...closes.size).each do |i|
        next if atr[i].nil?

        if i == @period
          st[i] = closes[i] <= upperband[i] ? upperband[i] : lowerband[i]
          next
        end

        st[i] = if st[i - 1] == upperband[i - 1]
                  closes[i] <= upperband[i] ? [upperband[i], st[i - 1]].min : lowerband[i]
                else
                  closes[i] >= lowerband[i] ? [lowerband[i], st[i - 1]].max : upperband[i]
                end
      end

      st
    end
  end
end
