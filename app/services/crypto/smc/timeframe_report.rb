# frozen_string_literal: true

module Crypto
  module Smc
    # Everything the SMC layer knows about one symbol on one timeframe.
    #
    # Built once per timeframe per scan and passed around read-only, so the
    # setup engine never re-derives structure and every check below is asking
    # the same set of swings the same question.
    class TimeframeReport
      attr_reader :timeframe, :series, :structure, :order_blocks, :fair_value_gaps,
                  :liquidity, :premium_discount, :price_action

      def initialize(series)
        @timeframe        = series.timeframe
        @series           = series
        @structure        = Structure.new(series)
        @order_blocks     = OrderBlocks.new(series, @structure)
        @fair_value_gaps  = FairValueGaps.new(series)
        @liquidity        = Liquidity.new(series, @structure)
        @premium_discount = PremiumDiscount.new(@structure.dealing_range)
        @price_action     = PriceAction.new(series)
      end

      def price = series.last_price
      delegate :atr, to: :series
      def bias = structure.trend

      def bullish? = bias == :bullish
      def bearish? = bias == :bearish

      # Points of interest in `direction` that price is currently sitting in
      # or approaching — order blocks first, then unfilled gaps.
      #
      # An already-tapped order block is kept but ranked behind a fresh one:
      # it is weaker, not dead, and on a 15m chart discarding it would often
      # leave no POI at all.
      def points_of_interest(direction)
        blocks = order_blocks.candidates(direction, price)
        gaps   = fair_value_gaps.candidates(direction, price)
        (blocks + gaps).sort_by { |zone| [zone.fresh? ? 0 : 1, zone.distance_from(price)] }
      end

      # The nearest POI price is actually interacting with, if any.
      def active_poi(direction, atr_multiple: 0.75)
        points_of_interest(direction).find { |zone| zone.near?(price, atr, multiple: atr_multiple) }
      end

      def summary
        {
          timeframe: timeframe,
          bias: bias,
          last_event: structure.last_event&.to_s,
          price: price,
          atr: atr.round(4),
          zone: premium_discount.zone(price),
          order_blocks: order_blocks.zones.size,
          fair_value_gaps: fair_value_gaps.zones.size
        }
      end
    end
  end
end
