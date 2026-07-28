# frozen_string_literal: true

module Crypto
  module Smc
    # Order blocks: the last opposing candle before the impulse that broke
    # structure.
    #
    # The break is what qualifies the candle. Any down candle can be pointed at
    # after the fact; only one that was immediately followed by displacement
    # through a swing high marks where size actually entered. So detection
    # starts from {Structure}'s events and walks *backwards* into the impulse,
    # rather than scanning for pretty candles and hoping.
    class OrderBlocks
      # How far back from a break to look for the originating candle. An
      # impulse that took more bars than this is not an impulse.
      IMPULSE_LOOKBACK = 12

      # Keep the most recent blocks only — a two-day-old 5m order block is
      # archaeology, not a level.
      MAX_ZONES = 6

      attr_reader :series, :structure, :zones

      def initialize(series, structure)
        @series    = series
        @structure = structure
        @zones     = detect
      end

      def bullish = zones.select(&:bullish?)
      def bearish = zones.select(&:bearish?)

      def for(direction)
        direction == :bullish ? bullish : bearish
      end

      # Valid zones in `direction`, nearest to price first.
      def candidates(direction, price = series.last_price)
        self.for(direction).select(&:valid?).sort_by { |z| z.distance_from(price) }
      end

      private

      def detect
        found = structure.events.filter_map { |event| build_zone(event) }
        found = dedupe(found)
        found.each { |zone| mark_state(zone) }
        found.last(MAX_ZONES)
      end

      def build_zone(event)
        origin = origin_candle(event)
        return nil unless origin

        Zone.new(kind: :order_block, direction: event.direction,
                 top: origin[:candle].high, bottom: origin[:candle].low,
                 index: origin[:index], time: origin[:candle].timestamp)
      end

      # The last candle against the break's direction, immediately preceding
      # the impulse leg.
      def origin_candle(event)
        start_idx = [event.index - 1, 0].max
        floor_idx = [event.index - IMPULSE_LOOKBACK, 0].max

        start_idx.downto(floor_idx) do |i|
          candle = series[i]
          next unless candle
          return { candle: candle, index: i } if event.bullish? ? candle.bearish? : candle.bullish?
        end

        nil
      end

      # Consecutive events often resolve to the same origin candle; one zone
      # per candle is enough.
      def dedupe(found)
        found.uniq { |zone| [zone.index, zone.direction] }
      end

      # Walks everything that printed after the zone formed and records
      # whether price has returned to it (tapped) or run through it
      # (invalidated). Invalidation is judged on closes; a wick through an
      # order block is exactly the sweep the block is there to produce.
      def mark_state(zone)
        series.candles.each_with_index do |candle, idx|
          next if idx <= zone.index + 1

          zone.tapped = true if candle.low <= zone.top && candle.high >= zone.bottom

          if zone.bullish?
            zone.invalidated = true if candle.close < zone.bottom
          elsif candle.close > zone.top
            zone.invalidated = true
          end
        end
      end
    end
  end
end
