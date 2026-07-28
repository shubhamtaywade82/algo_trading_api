# frozen_string_literal: true

module Crypto
  module Smc
    # Premium/discount pricing over the current dealing range, plus the
    # optimal-trade-entry band.
    #
    # The rule this encodes is the reason most of ICT's entry criteria exist:
    # buy in discount, sell in premium. A long taken at the top of the range is
    # the same idea as a long taken at the bottom, with the risk inverted.
    #
    # OTE is the 0.618–0.79 retracement of the leg — measured from the end of
    # the move, so a bullish leg's OTE sits in the lower half of the range.
    class PremiumDiscount
      OTE_START = 0.618
      OTE_END   = 0.79
      # Prices this close to the 50% mark are equilibrium rather than either
      # side of it — a razor-thin boundary would flip on a single tick.
      EQUILIBRIUM_BAND = 0.05

      attr_reader :high, :low

      def initialize(dealing_range)
        @high = dealing_range&.dig(:high)
        @low  = dealing_range&.dig(:low)
      end

      def valid?
        high.present? && low.present? && high > low
      end

      def range = valid? ? high - low : 0.0
      def equilibrium = valid? ? (high + low) / 2.0 : nil

      # Where price sits in the range, 0.0 at the low and 1.0 at the high.
      def position(price)
        return nil unless valid?

        ((price - low) / range).clamp(-1.0, 2.0)
      end

      # @return [Symbol, nil] :discount, :premium or :equilibrium
      def zone(price)
        pos = position(price)
        return nil if pos.nil?

        if (pos - 0.5).abs <= EQUILIBRIUM_BAND then :equilibrium
        elsif pos < 0.5 then :discount
        else
          :premium
        end
      end

      # Is price on the correct side of equilibrium for the intended trade?
      # Equilibrium itself is allowed — it is neutral, not wrong.
      def favourable?(price, direction)
        z = zone(price)
        return false if z.nil?
        return true if z == :equilibrium

        z == (direction == :bullish ? :discount : :premium)
      end

      # The 0.618–0.79 retracement band for a trade in `direction`.
      #
      # @return [Hash, nil] {top:, bottom:}
      def ote(direction)
        return nil unless valid?

        if direction == :bullish
          { top: high - (range * OTE_START), bottom: high - (range * OTE_END) }
        else
          { top: low + (range * OTE_END), bottom: low + (range * OTE_START) }
        end
      end

      def in_ote?(price, direction)
        band = ote(direction)
        return false if band.nil?

        price >= band[:bottom] && price <= band[:top]
      end

      def to_h
        { high: high, low: low, equilibrium: equilibrium }
      end
    end
  end
end
