# frozen_string_literal: true

# Builders for the crypto SMC specs.
#
# The detectors care about the *shape* of a price path, so the specs describe
# bars as plain [open, high, low, close] tuples and let this helper stamp
# sequential timestamps on them. Anything hand-built stays readable as a chart.
module CryptoCandleHelper
  BASE_TIME = Time.zone.parse('2026-01-05 00:00:00 UTC')

  # @param bars [Array<Array(Numeric, Numeric, Numeric, Numeric)>] o, h, l, c
  def crypto_series(bars, symbol: 'TESTUSDT', timeframe: '5m', interval: 300)
    candles = bars.each_with_index.map do |(o, h, l, c), i|
      Crypto::Candle.new(ts: BASE_TIME + (i * interval), open: o, high: h, low: l, close: c, volume: 100)
    end

    Crypto::Series.new(symbol: symbol, timeframe: timeframe, candles: candles)
  end

  # Binance-shaped kline rows, for client and parsing specs.
  def binance_rows(bars, start_ms: BASE_TIME.to_i * 1000, interval_ms: 300_000)
    bars.each_with_index.map do |(o, h, l, c), i|
      [start_ms + (i * interval_ms), o.to_s, h.to_s, l.to_s, c.to_s, '1000.5',
       start_ms + ((i + 1) * interval_ms) - 1, '0', 10, '0', '0', '0']
    end
  end

  # A zig-zag with a configurable per-leg drift: enough swings for structure to
  # have something to break, without hand-writing eighty bars.
  #
  # @param legs [Integer] number of up/down leg pairs
  # @param drift [Float] added to each leg's start, so the zig-zag trends
  def zigzag_bars(legs: 6, start: 100.0, amplitude: 4.0, drift: 0.0, step: 4)
    bars = []
    price = start

    legs.times do |leg|
      up = leg.even?
      step.times do
        delta = (up ? amplitude : -amplitude) / step
        o = price
        c = o + delta
        bars << [o, [o, c].max + 0.2, [o, c].min - 0.2, c]
        price = c
      end
      price += drift
    end

    bars
  end
end

RSpec.configure do |config|
  config.include CryptoCandleHelper
end
