# frozen_string_literal: true

module Market
  module Value
    class AvrzCalculator
      def self.call(mid:, atr_points:, vix:)
        new(mid: mid, atr_points: atr_points, vix: vix).call
      end

      def initialize(mid:, atr_points:, vix:)
        @mid = to_f_or_nil(mid)
        @atr = to_f_or_nil(atr_points)
        @vix = to_f_or_nil(vix)
      end

      def call
        return nil if @mid.nil? || @atr.nil?

        width = (@atr * vix_multiplier).round(2)

        {
          mid: @mid.round(2),
          low: (@mid - width).round(2),
          high: (@mid + width).round(2),
          width_points: width,
          regime: regime_label
        }
      end

      private

      def vix_multiplier
        return 1.0 if @vix.nil?
        return 1.2 if @vix > 14
        return 0.8 if @vix < 10

        1.0
      end

      def regime_label
        return 'unknown' if @vix.nil?
        return 'high' if @vix > 14
        return 'low' if @vix < 10

        'normal'
      end

      def to_f_or_nil(x)
        return nil if x.nil?

        Float(x, exception: false)
      end
    end
  end
end

