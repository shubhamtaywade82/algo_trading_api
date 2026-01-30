# frozen_string_literal: true

module Market
  module Value
    class VwapCalculator
      def self.session_vwap(series, session_date: Time.zone.today)
        new(series, from_ts: nil, session_date: session_date).vwap
      end

      def self.anchored_vwap(series, from_ts:, session_date: Time.zone.today)
        new(series, from_ts: from_ts, session_date: session_date).vwap
      end

      def initialize(series, from_ts:, session_date:)
        @series = series
        @from_ts = from_ts
        @session_date = session_date
      end

      def vwap
        rows = session_candles
        return nil if rows.empty?

        sum_pv = 0.0
        sum_v = 0.0
        prices = []

        rows.each do |c|
          vol = c.volume.to_f
          price = typical_price(c)
          prices << price

          next if vol <= 0

          sum_pv += price * vol
          sum_v += vol
        end

        # Some index feeds may publish candles with zero volume. Fall back to a
        # simple mean of typical prices so downstream logic has a stable mid.
        return prices.sum.fdiv(prices.size).round(2) if sum_v <= 0 && prices.any?

        (sum_pv / sum_v).round(2)
      end

      private

      def session_candles
        candles = @series.candles.select { |c| c.timestamp.to_date == @session_date }
        return candles if @from_ts.nil?

        candles.select { |c| c.timestamp >= @from_ts }
      end

      def typical_price(candle)
        (candle.high.to_f + candle.low.to_f + candle.close.to_f) / 3.0
      end
    end
  end
end

