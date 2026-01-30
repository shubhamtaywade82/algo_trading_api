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
      today = Time.zone.today
      prev_day = MarketCalendar.last_trading_day(from: today - 1)
      week_start = MarketCalendar.last_trading_day(from: today - 7)

      # Determine safe to_date based on session state
      # Don't use today's date if market hasn't closed yet (pre-open or weekend)
      now = Time.zone.now
      is_weekend = [0, 6].include?(now.wday)
      is_pre_open = !is_weekend && (now.hour < 9 || (now.hour == 9 && now.min < 15))
      is_post_close = !is_weekend && now.hour >= 15 && now.min >= 30

      if is_pre_open || is_weekend
        # Use previous trading day as end date (don't query today)
        to_date_prev = prev_day
        to_date_week = prev_day
      elsif is_post_close && MarketCalendar.trading_day?(today)
        # Market closed today and it was a trading day - can use today
        to_date_prev = today
        to_date_week = today
      else
        # Market is live - use previous trading day to be safe
        to_date_prev = prev_day
        to_date_week = prev_day
      end

      # For prev_day range, use day before as from_date to ensure from_date < to_date
      from_date_prev = MarketCalendar.last_trading_day(from: prev_day - 1)

      # Add delays between API calls to avoid rate limiting
      bars_prev = vix_instrument.historical_ohlc(from_date: from_date_prev.to_s, to_date: to_date_prev.to_s) || {}
      sleep(1.2) # Rate limit: ~1 call per second

      bars_week = vix_instrument.historical_ohlc(from_date: week_start.to_s, to_date: to_date_week.to_s) || {}
      sleep(1.2) # Rate limit: ~1 call per second

      pdh = Array(bars_prev['high']).map(&:to_f).max
      pwl = Array(bars_week['low']).map(&:to_f).min

      # Add delay before LTP call
      sleep(1.2)
      vix_price = vix_instrument.ltp.to_f

      Snapshot.new(
        price: vix_price,
        slope: Indicators::Slope.call(series: vix_series_5m, lookback: 24),
        pdh: pdh,
        pwl: pwl
      )
    end
  end
end

