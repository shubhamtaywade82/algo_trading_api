# frozen_string_literal: true

module Crypto
  module Smc
    # Market structure: the sequence of BOS and CHoCH events that defines
    # directional bias on a timeframe.
    #
    #   BOS   (Break of Structure)     — price closes beyond the most recent
    #                                    swing *in the direction it was already
    #                                    trending*. Continuation.
    #   CHoCH (Change of Character)    — the same break, but against the
    #                                    prevailing trend. The first warning
    #                                    that the leg is over.
    #
    # Two rules make the output tradable rather than merely plausible:
    #
    # 1. A break is confirmed on a **close**, not a wick. A wick through a
    #    swing high that closes back below is a liquidity sweep — the opposite
    #    signal — and {Liquidity} is what reads it.
    # 2. A pivot is only usable from `confirmed_at` onward. A fractal at bar i
    #    is not knowable until i + strength has printed, so walking bars with
    #    the full pivot list in hand would break structure against levels the
    #    market had not yet formed and report signals that never existed live.
    class Structure
      Event = Struct.new(:type, :direction, :level, :index, :time, keyword_init: true) do
        def bullish? = direction == :bullish
        def bearish? = direction == :bearish
        def choch?   = type == :choch
        def bos?     = type == :bos
        def to_s     = "#{type.to_s.upcase} #{direction}"
      end

      attr_reader :series, :strength, :events, :swing_highs, :swing_lows

      def initialize(series, strength: Config.swing_strength)
        @series      = series
        @strength    = strength
        @swing_highs = series.swing_highs(strength: strength)
        @swing_lows  = series.swing_lows(strength: strength)
        @events      = detect_events
      end

      # @return [Symbol] :bullish, :bearish or :neutral
      def trend
        last_event&.direction || :neutral
      end

      def last_event = events.last

      # Most recent event in a given direction, within `lookback` bars of the
      # end of the series. Used to ask "did 5m just shift up?" without
      # accepting a shift from two sessions ago.
      def recent_event(direction: nil, type: nil, lookback: 30)
        cutoff = series.size - lookback
        events.reverse_each.find do |event|
          event.index >= cutoff &&
            (direction.nil? || event.direction == direction) &&
            (type.nil? || event.type == type)
        end
      end

      def bullish? = trend == :bullish
      def bearish? = trend == :bearish

      # The swing high above / swing low below current price — where resting
      # liquidity sits, and therefore where a move is drawn to.
      def next_liquidity_above(price = series.last_price)
        swing_highs.pluck(:price).select { |p| p > price }.min
      end

      def next_liquidity_below(price = series.last_price)
        swing_lows.pluck(:price).select { |p| p < price }.max
      end

      # The high/low pair defining the current leg, for premium/discount work.
      # Falls back to the series extremes when there are too few pivots.
      #
      # @return [Hash, nil] {high:, low:, high_time:, low_time:}
      def dealing_range(lookback: 60)
        recent = ->(pivots) { pivots.select { |p| p[:index] >= series.size - lookback } }
        highs = recent.call(swing_highs)
        lows  = recent.call(swing_lows)

        high = highs.max_by { |p| p[:price] }
        low  = lows.min_by { |p| p[:price] }
        return fallback_range(lookback) if high.nil? || low.nil?

        { high: high[:price], low: low[:price], high_time: high[:time], low_time: low[:time] }
      end

      private

      def fallback_range(lookback)
        window = series.candles.last(lookback)
        return nil if window.empty?

        { high: window.map(&:high).max, low: window.map(&:low).min, high_time: nil, low_time: nil }
      end

      # Walks the series once, holding the most recent *confirmed and unbroken*
      # pivot on each side, and emits an event whenever a close clears one.
      def detect_events
        return [] if series.size < ((strength * 2) + 2)

        @detected = []
        @running_trend = :neutral
        @active = { high: nil, low: nil }
        @by_confirmation = {
          high: swing_highs.group_by { |s| s[:confirmed_at] },
          low: swing_lows.group_by { |s| s[:confirmed_at] }
        }

        series.candles.each_with_index { |candle, idx| step(candle, idx) }
        @detected
      end

      def step(candle, idx)
        activate_pivots(idx)
        broke?(candle, idx, :high) || broke?(candle, idx, :low)
      end

      # A pivot becomes usable at its confirmation bar, and the latest one on
      # each side is the level structure is measured against.
      def activate_pivots(idx)
        %i[high low].each do |side|
          confirmed = @by_confirmation[side][idx]
          @active[side] = confirmed.max_by { |s| s[:index] } if confirmed
        end
      end

      def broke?(candle, idx, side)
        pivot = @active[side]
        return false if pivot.nil?
        return false unless side == :high ? candle.close > pivot[:price] : candle.close < pivot[:price]

        record(side == :high ? :bullish : :bearish, pivot[:price], idx, candle.timestamp)
        @active[side] = nil
        true
      end

      def record(direction, level, index, time)
        # The first break of a series has no prior trend to contradict, so it
        # is a BOS rather than a change of character.
        type = @running_trend != :neutral && @running_trend != direction ? :choch : :bos
        @detected << Event.new(type: type, direction: direction, level: level, index: index, time: time)
        @running_trend = direction
      end
    end
  end
end
