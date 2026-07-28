# frozen_string_literal: true

module Crypto
  # An ordered, in-memory run of {Crypto::Candle} for one symbol/timeframe,
  # plus the handful of measurements the SMC layer needs from raw price.
  #
  # Oldest candle first, newest last — every index in this namespace follows
  # that convention, and the SMC detectors rely on it.
  class Series
    include Enumerable

    attr_reader :symbol, :timeframe, :candles

    def initialize(symbol:, timeframe:, candles: [])
      @symbol    = symbol
      @timeframe = timeframe
      @candles   = candles
    end

    def self.from_binance(symbol:, timeframe:, rows:)
      new(symbol: symbol, timeframe: timeframe, candles: rows.map { |row| Candle.from_binance(row) })
    end

    def each(&) = candles.each(&)
    delegate :size, to: :candles
    delegate :empty?, to: :candles
    delegate :[], to: :candles
    def last(count = nil) = count ? candles.last(count) : candles.last

    def opens   = candles.map(&:open)
    def highs   = candles.map(&:high)
    def lows    = candles.map(&:low)
    def closes  = candles.map(&:close)
    def volumes = candles.map(&:volume)

    def last_price = candles.last&.close
    def last_time  = candles.last&.timestamp

    # Average true range over the last `period` bars.
    #
    # A simple mean rather than Wilder's smoothing: everything downstream uses
    # ATR as a distance yardstick (stop buffers, equal-high tolerance,
    # displacement thresholds), where the two differ by less than the noise
    # they are measuring.
    #
    # @return [Float] 0.0 when there is not enough history to measure
    def atr(period = 14)
      return 0.0 if candles.size < 2

      trs = true_ranges.last(period)
      return 0.0 if trs.empty?

      trs.sum / trs.size
    end

    def ema(period)
      values = closes
      return [] if values.size < period

      k = 2.0 / (period + 1)
      seed = values.first(period).sum / period.to_f
      out = [seed]
      values.drop(period).each { |price| out << (((price - out.last) * k) + out.last) }
      out
    end

    # Fractal pivot highs: bar `i` is a swing high when its high is the
    # highest across `strength` bars either side.
    #
    # `confirmed_at` is the bar by which the pivot is *knowable* — a pivot at
    # index i cannot be traded until i + strength has printed. Structure
    # detection walks bars in order and must not use a pivot before then, or
    # it reads the future.
    #
    # @return [Array<Hash>] {index:, price:, time:, confirmed_at:}
    def swing_highs(strength: Config.swing_strength)
      pivots(strength: strength, kind: :high)
    end

    def swing_lows(strength: Config.swing_strength)
      pivots(strength: strength, kind: :low)
    end

    # @return [Float, nil] highest high of the last `count` bars
    def highest(count = size)  = highs.last(count).max
    def lowest(count = size)   = lows.last(count).min

    private

    def true_ranges
      candles.each_cons(2).map do |prev, cur|
        [cur.high - cur.low, (cur.high - prev.close).abs, (cur.low - prev.close).abs].max
      end
    end

    def pivots(strength:, kind:)
      return [] if candles.size < ((strength * 2) + 1)

      series = kind == :high ? highs : lows
      out = []

      (strength...(candles.size - strength)).each do |i|
        window = series[(i - strength)..(i + strength)]
        pivot  = series[i]
        extreme = kind == :high ? window.max : window.min
        next unless pivot == extreme
        # A flat cluster would otherwise report every bar in it as a pivot;
        # keep the first and let the rest fall through.
        next if window.count(extreme) > 1 && series[(i - strength)...i].include?(extreme)

        out << { index: i, price: pivot, time: candles[i].timestamp, confirmed_at: i + strength }
      end

      out
    end
  end
end
