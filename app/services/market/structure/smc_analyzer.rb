# frozen_string_literal: true

module Market
  module Structure
    class SmcAnalyzer
      Result = Struct.new(
        :timeframe_minutes,
        :as_of,
        :market_structure,
        :last_swing_high,
        :last_swing_low,
        :last_bos,
        keyword_init: true
      )

      def self.call(series, timeframe_minutes:)
        new(series, timeframe_minutes: timeframe_minutes).call
      end

      def initialize(series, timeframe_minutes:)
        @series = series
        @timeframe_minutes = timeframe_minutes.to_i
      end

      def call
        return nil if candles.empty?

        swing_high = last_swing_high
        swing_low = last_swing_low

        Result.new(
          timeframe_minutes: @timeframe_minutes,
          as_of: candles.last.timestamp,
          market_structure: infer_structure(swing_high, swing_low),
          last_swing_high: swing_high,
          last_swing_low: swing_low,
          last_bos: last_break_of_structure(swing_high, swing_low)
        )
      end

      private

      def candles
        @candles ||= @series.candles
      end

      def infer_structure(swing_high, swing_low)
        return :unknown if swing_high.nil? || swing_low.nil?

        close = candles.last.close.to_f
        return :bullish if close > swing_high[:price]
        return :bearish if close < swing_low[:price]

        :range
      end

      def last_swing_high
        swing = swing_points(:high)
        swing.last
      end

      def last_swing_low
        swing = swing_points(:low)
        swing.last
      end

      def swing_points(type, lookback: 2)
        return [] if candles.size < ((lookback * 2) + 1)

        points = []

        (lookback...(candles.size - lookback)).each do |i|
          c = candles[i]
          left = candles[(i - lookback)...i]
          right = candles[(i + 1)..(i + lookback)]

          value = type == :high ? c.high : c.low
          left_values = left.map { |x| type == :high ? x.high : x.low }
          right_values = right.map { |x| type == :high ? x.high : x.low }

          is_swing =
            if type == :high
              value > left_values.max && value > right_values.max
            else
              value < left_values.min && value < right_values.min
            end

          next unless is_swing

          points << { price: value.to_f, ts: c.timestamp }
        end

        points
      end

      def last_break_of_structure(swing_high, swing_low)
        return nil if swing_high.nil? || swing_low.nil?

        close = candles.last.close.to_f
        return { direction: :bullish, level: swing_high[:price], ts: candles.last.timestamp } if close > swing_high[:price]
        return { direction: :bearish, level: swing_low[:price], ts: candles.last.timestamp } if close < swing_low[:price]

        nil
      end
    end
  end
end

