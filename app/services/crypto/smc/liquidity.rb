# frozen_string_literal: true

module Crypto
  module Smc
    # Liquidity: where stops are resting, and when they have just been taken.
    #
    # Equal highs and equal lows are pools — obvious levels a crowd puts stops
    # behind. A **sweep** is the moment one is raided: price wicks through the
    # level and closes back inside. That close is what separates a sweep from a
    # break; {Structure} handles the latter and reads the same bar as
    # continuation, so the close test has to be strict in both places or the
    # two detectors will contradict each other on the same candle.
    #
    # Directional convention, which is the opposite of what the wick looks
    # like: taking out highs (buy-side liquidity) and rejecting is *bearish*;
    # taking out lows (sell-side liquidity) and rejecting is *bullish*.
    class Liquidity
      Sweep = Struct.new(:direction, :level, :index, :time, :penetration, keyword_init: true) do
        def bullish? = direction == :bullish
        def bearish? = direction == :bearish
      end

      # `strength` is how many pivots formed the pool — two equal highs are a
      # pool, five are a magnet. Not named `count`: that would shadow
      # Struct#count and read as an element count rather than a touch count.
      Pool = Struct.new(:side, :price, :strength, :time, keyword_init: true)

      # Two pivots within this fraction of ATR count as "equal".
      EQUALITY_ATR_FRACTION = 0.12

      attr_reader :series, :structure, :sweeps, :pools

      def initialize(series, structure)
        @series    = series
        @structure = structure
        @atr       = series.atr
        @sweeps    = detect_sweeps
        @pools     = detect_pools
      end

      # Most recent sweep in `direction` inside the last `lookback` bars.
      #
      # A sweep from fifty bars ago is history; the setup engine only cares
      # about one price is still reacting to.
      def recent_sweep(direction, lookback: 20)
        cutoff = series.size - lookback
        sweeps.reverse_each.find { |s| s.direction == direction && s.index >= cutoff }
      end

      def equal_highs = pools.select { |p| p.side == :high }
      def equal_lows  = pools.select { |p| p.side == :low }

      # Nearest untouched pool above/below price — the natural draw for a move,
      # and therefore the target the setup engine reaches for first.
      def target_above(price = series.last_price)
        equal_highs.map(&:price).select { |p| p > price }.min
      end

      def target_below(price = series.last_price)
        equal_lows.map(&:price).select { |p| p < price }.max
      end

      private

      def detect_sweeps
        found = []
        seen = Set.new

        series.candles.each_with_index do |candle, idx|
          swept_high = raided(structure.swing_highs, idx) { |level| candle.high > level && candle.close < level }
          if swept_high && seen.add?([:bearish, swept_high])
            found << Sweep.new(direction: :bearish, level: swept_high, index: idx,
                               time: candle.timestamp, penetration: candle.high - swept_high)
          end

          swept_low = raided(structure.swing_lows, idx) { |level| candle.low < level && candle.close > level }
          next unless swept_low && seen.add?([:bullish, swept_low])

          found << Sweep.new(direction: :bullish, level: swept_low, index: idx,
                             time: candle.timestamp, penetration: swept_low - candle.low)
        end

        found
      end

      # Tests bar `idx` against the *most recent* pivot that was knowable
      # before it — not every pivot in history.
      #
      # Checking them all was the first version and it was useless: in any
      # oscillating market almost every bar wicks past one of the dozens of
      # old pivots lying around and closes back inside, which reported a sweep
      # on half the candles in the series and made the signal worth nothing.
      # A sweep is a raid on the level traders are actually watching, which is
      # the latest one.
      def raided(pivots, idx)
        pivot = pivots.reverse_each.find { |p| p[:confirmed_at] <= idx && p[:index] < idx }
        return nil if pivot.nil?

        yield(pivot[:price]) ? pivot[:price] : nil
      end

      def detect_pools
        cluster(structure.swing_highs, :high) + cluster(structure.swing_lows, :low)
      end

      def cluster(pivots, side)
        tolerance = equality_tolerance
        return pivots.map { |pivot| pool_from([pivot], side) } if tolerance.nil?

        bucket_by_price(pivots, tolerance).map { |bucket| pool_from(bucket, side) }
      end

      # Without an ATR to scale against there is no meaningful notion of
      # "equal", so every pivot stands alone.
      def equality_tolerance
        @atr.positive? ? @atr * EQUALITY_ATR_FRACTION : nil
      end

      def bucket_by_price(pivots, tolerance)
        pivots.sort_by { |p| p[:price] }.each_with_object([]) do |pivot, buckets|
          bucket = buckets.find { |b| (b.first[:price] - pivot[:price]).abs <= tolerance }
          bucket ? bucket << pivot : buckets << [pivot]
        end
      end

      # The pool sits at the extreme of its bucket — that is the level the
      # stops are actually behind.
      def pool_from(bucket, side)
        prices = bucket.pluck(:price)

        Pool.new(side: side,
                 price: side == :high ? prices.max : prices.min,
                 strength: bucket.size,
                 time: bucket.max_by { |p| p[:index] }[:time])
      end
    end
  end
end
