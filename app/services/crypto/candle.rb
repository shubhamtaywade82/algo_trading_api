# frozen_string_literal: true

module Crypto
  # Immutable OHLCV bar for a crypto pair.
  #
  # Deliberately *not* the app's top-level `Candle`: that one rounds every
  # price through `PriceMath.round_tick` (an NSE 0.05 tick) and casts volume
  # with `to_i`. Both are wrong here — ETHUSDT prints to two decimals on a
  # 0.01 tick, SOLUSDT to three, and Binance reports fractional base volume.
  class Candle
    attr_reader :timestamp, :open, :high, :low, :close, :volume

    # @param ts [Time, Integer] bar open time; Integer is read as epoch millis
    def initialize(ts:, open:, high:, low:, close:, volume: 0)
      @timestamp = coerce_time(ts)
      @open      = open.to_f
      @high      = high.to_f
      @low       = low.to_f
      @close     = close.to_f
      @volume    = volume.to_f
    end

    # Binance returns klines as positional arrays:
    # [open_time, open, high, low, close, volume, close_time, ...]
    def self.from_binance(row)
      new(ts: row[0], open: row[1], high: row[2], low: row[3], close: row[4], volume: row[5])
    end

    def bullish? = close > open
    def bearish? = close < open
    def doji?    = (close - open).abs < (range * 0.05)

    def body        = (close - open).abs
    def range       = high - low
    def upper_wick  = high - [open, close].max
    def lower_wick  = [open, close].min - low
    def midpoint    = (high + low) / 2.0

    # Share of the bar that is body rather than wick. Displacement candles run
    # high; indecision bars run low.
    def body_ratio
      return 0.0 if range.zero?

      body / range
    end

    def to_h
      { timestamp: timestamp, open: open, high: high, low: low, close: close, volume: volume }
    end

    private

    def coerce_time(ts)
      case ts
      when Time, ActiveSupport::TimeWithZone then ts
      when Numeric then Time.zone.at(ts / 1000.0)
      else Time.zone.parse(ts.to_s)
      end
    end
  end
end
