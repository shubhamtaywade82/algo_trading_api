# frozen_string_literal: true

module Option
  module Components
    class Guidance
      def initialize(ctx) = @ctx = ctx

      def selection_snapshot(signal_type:, filtered:, ranked:)
        {
          total_strikes: @ctx.oc[:oc].keys.size,
          filtered_count: filtered.size,
          ranked_count: ranked.size,
          top_score: ranked.first&.dig(:score)&.round(2),
          filters_applied: filter_summary(signal_type: signal_type, filtered: filtered),
          strike_guidance: recommended(signal_type)
        }
      end

      def filter_summary(signal_type:, filtered:)
        atm = @ctx.atm_strike
        return { total_strikes: @ctx.oc[:oc].keys.size, filtered_count: 0, atm_strike: atm, filters_applied: [] } if filtered.empty?

        {
          total_strikes: @ctx.oc[:oc].keys.size,
          filtered_count: filtered.size,
          atm_strike: atm,
          filters_applied: filtered.map do |opt|
            dist = (opt[:strike_price] - atm).abs
            atm_range = @ctx.atm_range_pct * @ctx.spot
            {
              strike_price: opt[:strike_price],
              reasons: ['PASSED'],
              distance_from_atm: dist,
              atm_range_multiple: dist / atm_range,
              delta: opt[:greeks][:delta].abs,
              iv: opt[:iv],
              price: opt[:last_price]
            }
          end
        }
      end

      def recommended(signal_type)
        atm = @ctx.atm_strike
        return {} unless atm

        recs =
          if signal_type == :ce
            [atm, @ctx.snap_to_grid(atm + @ctx.strike_step), @ctx.snap_to_grid(atm + (2 * @ctx.strike_step))]
          elsif signal_type == :pe
            [atm, @ctx.snap_to_grid(atm - @ctx.strike_step), @ctx.snap_to_grid(atm - (2 * @ctx.strike_step))]
          else
            [atm]
          end

        recs = recs.compact.uniq.select { |s| @ctx.oc_strikes.include?(s) }

        {
          current_spot: @ctx.spot,
          atm_strike: atm,
          strike_step: @ctx.strike_step,
          recommended_strikes: recs,
          explanation: (if signal_type == :ce
                          'CE strikes should be ATM or slightly OTM (never ITM)'
                        else
                          'PE strikes should be ATM or slightly OTM (never ITM)'
                        end)
        }
      end
    end
  end
end
