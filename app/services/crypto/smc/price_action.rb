# frozen_string_literal: true

module Crypto
  module Smc
    # Raw candle behaviour: displacement, engulfing and rejection wicks.
    #
    # These are the confirmations, never the reason for a trade. The setup
    # engine weights them lightly for exactly that reason — an engulfing candle
    # inside a range is a coin flip, while the same candle out of a swept
    # discount order block is the entry.
    #
    # Every threshold is ATR-relative so one set of numbers works on a $4,000
    # ETH candle and a $150 SOL candle.
    class PriceAction
      DISPLACEMENT_ATR_MULTIPLE = 1.15
      DISPLACEMENT_BODY_RATIO   = 0.55
      ENGULFING_BODY_RATIO      = 0.5
      REJECTION_WICK_RATIO      = 0.55

      attr_reader :series

      def initialize(series)
        @series = series
        @atr    = series.atr
      end

      # A candle whose body is large relative to recent range — the footprint
      # of an aggressive market participant rather than a drift.
      def displacement(direction, lookback: 5)
        recent(lookback).reverse_each.find do |candle|
          next false unless directional?(candle, direction)

          candle.body >= (@atr * DISPLACEMENT_ATR_MULTIPLE) && candle.body_ratio >= DISPLACEMENT_BODY_RATIO
        end
      end

      def displacement?(direction, lookback: 5) = displacement(direction, lookback: lookback).present?

      # Engulfing: the current body fully covers the previous body against the
      # previous candle's direction.
      def engulfing(direction, lookback: 3)
        pairs(lookback).reverse_each do |prev, cur|
          next unless directional?(cur, direction)
          next unless prev.body.positive? && cur.body >= prev.body
          next unless cur.body_ratio >= ENGULFING_BODY_RATIO

          covered = if direction == :bullish
                      cur.close >= [prev.open, prev.close].max && cur.open <= [prev.open, prev.close].min
                    else
                      cur.close <= [prev.open, prev.close].min && cur.open >= [prev.open, prev.close].max
                    end
          return cur if covered
        end
        nil
      end

      def engulfing?(direction, lookback: 3) = engulfing(direction, lookback: lookback).present?

      # A long wick against the intended direction: price probed and was
      # refused.
      def rejection(direction, lookback: 3)
        recent(lookback).reverse_each.find do |candle|
          next false unless candle.range.positive?

          wick = direction == :bullish ? candle.lower_wick : candle.upper_wick
          wick / candle.range >= REJECTION_WICK_RATIO
        end
      end

      def rejection?(direction, lookback: 3) = rejection(direction, lookback: lookback).present?

      private

      def recent(count) = series.candles.last(count)

      def pairs(count) = series.candles.last(count + 1).each_cons(2).to_a

      def directional?(candle, direction)
        direction == :bullish ? candle.bullish? : candle.bearish?
      end
    end
  end
end
