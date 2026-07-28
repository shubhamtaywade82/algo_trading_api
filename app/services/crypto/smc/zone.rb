# frozen_string_literal: true

module Crypto
  module Smc
    # A price band that acts as a point of interest — an order block, a fair
    # value gap, or anything else the detectors want to hand to the setup
    # engine in a uniform shape.
    #
    # `tapped` and `invalidated` are tracked separately on purpose. A zone
    # price has merely touched is still in play (that touch is the entry); a
    # zone price has *closed through* is gone, and treating the two the same
    # is how a scanner ends up buying into a broken level.
    class Zone
      attr_reader :kind, :direction, :top, :bottom, :index, :time
      attr_accessor :tapped, :invalidated

      def initialize(kind:, direction:, top:, bottom:, index:, time:)
        @kind        = kind
        @direction   = direction
        @top         = [top, bottom].max.to_f
        @bottom      = [top, bottom].min.to_f
        @index       = index
        @time        = time
        @tapped      = false
        @invalidated = false
      end

      def tapped?      = tapped
      def invalidated? = invalidated
      def fresh?       = !tapped && !invalidated
      def valid?       = !invalidated

      def bullish? = direction == :bullish
      def bearish? = direction == :bearish

      def height   = top - bottom
      def midpoint = (top + bottom) / 2.0

      def contains?(price) = price >= bottom && price <= top

      # Distance from price to the near edge of the zone, 0 when inside.
      def distance_from(price)
        return 0.0 if contains?(price)

        price > top ? price - top : bottom - price
      end

      # Is price close enough to treat the zone as live? Measured in ATR so a
      # 4h zone on ETH and a 5m zone on SOL are judged on the same scale.
      def near?(price, atr, multiple: 0.75)
        return contains?(price) if atr.to_f <= 0

        distance_from(price) <= (atr * multiple)
      end

      def label
        "#{direction == :bullish ? 'Bullish' : 'Bearish'} #{kind.to_s.tr('_', ' ').upcase}"
      end

      def to_h
        { kind: kind, direction: direction, top: top, bottom: bottom, time: time,
          tapped: tapped, invalidated: invalidated }
      end
    end
  end
end
