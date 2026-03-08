# frozen_string_literal: true

module CandleSeriesModules
  # Price action utilities for CandleSeries
  module PriceAction
    def swing_high?(index, lookback = 2)
      res = _swing?(:high, :>, index, lookback)
      { swing_high: res }
    end

    def swing_low?(index, lookback = 2)
      res = _swing?(:low, :<, index, lookback)
      { swing_low: res }
    end

    def recent_highs(n = 20) = { highs: candles.last(n).map(&:high) }
    def recent_lows(n = 20)  = { lows:  candles.last(n).map(&:low)  }

    def previous_swing_high = recent_highs.sort[-2]
    def previous_swing_low  = recent_lows.sort[1]

    def liquidity_grab_up?(lookback: 20)
      res = _liquidity?(:up, lookback)
      { liquidity_grab_up: res }
    end

    def liquidity_grab_down?(lookback: 20)
      res = _liquidity?(:down, lookback)
      { liquidity_grab_down: res }
    end

    def inside_bar?(i)
      return false if i < 1

      curr = candles[i]
      prev = candles[i - 1]
      curr.high < prev.high && curr.low > prev.low
    end

    private

    def _swing?(attr, cmp, index, lookback)
      return false if index < lookback || index + lookback >= candles.size

      current = candles[index].public_send(attr)
      left    = candles[(index - lookback)...index].map(&attr)
      right   = candles[(index + 1)..(index + lookback)].map(&attr)

      cmp == :> ? (current > left.max && current > right.max) : (current < left.min && current < right.min)
    end

    def _liquidity?(dir, lookback)
      if dir == :up
        # use previous local swing high within lookback window
        high_prev = highs.last(lookback + 1)[0...-1].max
        high_now  = highs.last
        high_now > high_prev && closes.last < high_prev && candles.last.bearish?
      else
        low_prev = lows.last(lookback + 1)[0...-1].min
        low_now  = lows.last
        low_now < low_prev && closes.last > low_prev && candles.last.bullish?
      end
    end
  end
end
