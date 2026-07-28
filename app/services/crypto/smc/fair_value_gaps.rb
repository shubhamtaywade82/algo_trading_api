# frozen_string_literal: true

module Crypto
  module Smc
    # Fair value gaps (ICT imbalances): a three-candle formation where the
    # middle candle moved fast enough that the wicks either side never
    # overlapped, leaving a band of price that was only ever traded in one
    # direction.
    #
    #   bullish  low[i] > high[i-2]   → gap between high[i-2] and low[i]
    #   bearish  high[i] < low[i-2]   → gap between high[i] and low[i-2]
    #
    # Tiny gaps are noise on any timeframe, so a gap must be worth at least
    # MIN_ATR_FRACTION of ATR to be recorded.
    class FairValueGaps
      MIN_ATR_FRACTION = 0.12
      MAX_ZONES = 8

      attr_reader :series, :zones

      def initialize(series)
        @series = series
        @atr    = series.atr
        @zones  = detect
      end

      def bullish = zones.select(&:bullish?)
      def bearish = zones.select(&:bearish?)

      def for(direction)
        direction == :bullish ? bullish : bearish
      end

      # Unfilled gaps in `direction`, nearest to price first. An unfilled gap
      # is the one still holding an imbalance, and therefore the one price has
      # a reason to revisit.
      def candidates(direction, price = series.last_price)
        self.for(direction).reject(&:invalidated?).sort_by { |z| z.distance_from(price) }
      end

      private

      def detect
        found = []

        (2...series.size).each do |i|
          prev2 = series[i - 2]
          cur   = series[i]

          if cur.low > prev2.high
            found << gap(:bullish, top: cur.low, bottom: prev2.high, index: i, time: cur.timestamp)
          elsif cur.high < prev2.low
            found << gap(:bearish, top: prev2.low, bottom: cur.high, index: i, time: cur.timestamp)
          end
        end

        found = found.compact
        found.each { |zone| mark_state(zone) }
        found.last(MAX_ZONES)
      end

      def gap(direction, top:, bottom:, index:, time:)
        height = top - bottom
        return nil if @atr.positive? && height < (@atr * MIN_ATR_FRACTION)
        return nil unless height.positive?

        Zone.new(kind: :fvg, direction: direction, top: top, bottom: bottom, index: index, time: time)
      end

      # A gap is tapped once price trades back into it and invalidated
      # ("filled") once price has traded all the way through — at that point
      # the imbalance it represented no longer exists.
      def mark_state(zone)
        series.candles.each_with_index do |candle, idx|
          next if idx <= zone.index

          zone.tapped = true if candle.low <= zone.top && candle.high >= zone.bottom

          if zone.bullish?
            zone.invalidated = true if candle.low <= zone.bottom
          elsif candle.high >= zone.top
            zone.invalidated = true
          end
        end
      end
    end
  end
end
