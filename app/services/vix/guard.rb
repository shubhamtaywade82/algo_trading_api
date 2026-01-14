# frozen_string_literal: true

module Vix
  class Guard
    MAX_SLOPE_POINTS_PER_CANDLE = 0.02

    Snapshot = Struct.new(
      :price,
      :slope,
      :pdh,
      :pwl,
      keyword_init: true
    ) do
      def range_regime?
        slope.to_f.abs < MAX_SLOPE_POINTS_PER_CANDLE &&
          price.to_f >= pwl.to_f &&
          price.to_f <= pdh.to_f
      end
    end

    def self.snapshot(vix_instrument:, vix_series_5m:)
      trade_day = MarketCalendar.today_or_last_trading_day
      prev_day = MarketCalendar.last_trading_day(from: trade_day - 1)
      week_start = MarketCalendar.last_trading_day(from: trade_day - 7)

      bars_prev = vix_instrument.historical_ohlc(from_date: prev_day.to_s, to_date: trade_day.to_s) || {}
      bars_week = vix_instrument.historical_ohlc(from_date: week_start.to_s, to_date: trade_day.to_s) || {}

      pdh = Array(bars_prev['high']).map(&:to_f).max
      pwl = Array(bars_week['low']).map(&:to_f).min

      Snapshot.new(
        price: vix_instrument.ltp.to_f,
        slope: Indicators::Slope.call(series: vix_series_5m, lookback: 24),
        pdh: pdh,
        pwl: pwl
      )
    end
  end
end

