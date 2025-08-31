# frozen_string_literal: true

module Option
  module Components
    class Context
      IV_RANK_MIN        = 0.00
      IV_RANK_MAX        = 0.80
      THETA_AVOID_HOUR   = 14.5
      MIN_ADX_VALUE_PROD = 18
      MIN_ADX_VALUE_DEV  = 10

      attr_reader :oc, :expiry, :spot, :iv_rank, :hist, :ta, :strike_step

      def initialize(option_chain:, expiry:, underlying_spot:, iv_rank:, historical:, strike_step:)
        @oc     = option_chain.with_indifferent_access
        @expiry = Date.parse(expiry.to_s)
        @spot   = underlying_spot.to_f
        @iv_rank = iv_rank.to_f
        @hist    = historical || []
        @ta      = Indicators::HolyGrail.call(candles: hist) if hist.present?
        @strike_step = strike_step || infer_strike_step
      end

      # -------- market state (memoized) -------------
      def oc_strikes
        @oc_strikes ||= oc[:oc].keys.map(&:to_f).sort
      end

      def atm_strike
        return nil if oc_strikes.empty?

        ref = (oc[:last_price] || spot).to_f
        oc_strikes.min_by { |s| (s - ref).abs }
      end

      def adx
        ta&.adx
      end

      def momentum
        ta ? ta.momentum.to_sym : :flat
      end

      def trend
        ta ? ta.bias.to_sym : intraday_trend
      end

      def adx_min
        Rails.env.production? ? MIN_ADX_VALUE_PROD : MIN_ADX_VALUE_DEV
      end

      def ta_snapshot
        ta ? ta.to_h : {}
      end

      # ---------- time & session ----------
      def theta_late_entry?
        now = Time.zone.now
        expiry == now.to_date && (now.hour + (now.min / 60.0)) > THETA_AVOID_HOUR
      end

      # ---------- volatility window ----------
      def atm_range_pct
        case iv_rank
        when 0.0..0.2 then 0.01
        when 0.2..0.5 then 0.015
        else 0.025
        end
      end

      # ---------- delta thresholds ----------
      def min_delta_for(strike_price)
        base =
          if Time.zone.now.hour >= 14
            0.45
          elsif Time.zone.now.hour >= 13
            0.35
          elsif Time.zone.now.hour >= 11
            0.30
          else
            0.25
          end

        return base unless strike_step && atm_strike

        steps_away = ((strike_price - atm_strike).abs / strike_step.to_f).round
        [base - (0.05 * steps_away), 0.20].max
      end

      # ---------- grid utils ----------
      def snap_to_grid(strike)
        return nil if oc_strikes.empty? || atm_strike.nil?

        delta  = strike - atm_strike
        steps  = (delta / strike_step.to_f).round
        target = atm_strike + (steps * strike_step.to_f)
        oc_strikes.min_by { |s| (s - target).abs }
      end

      private

      def infer_strike_step
        diffs = oc_strikes.each_cons(2).map { |a, b| (b - a).abs }.reject(&:zero?)
        step  = diffs.group_by(&:round).max_by { |_k, v| v.size }&.first&.to_f
        step&.positive? ? step : 50.0
      end

      # light fallback if TA not present
      def intraday_trend
        window = 3
        sums = { ce: 0.0, pe: 0.0 }
        return :neutral unless atm_strike

        oc_strikes.select { |s| (s - atm_strike).abs <= window * 100 }.each do |s|
          key = format('%.6f', s)
          %i[ce pe].each do |side|
            opt = oc.dig(:oc, key, side.to_s)
            next unless opt

            change = opt['last_price'].to_f - opt['previous_close_price'].to_f
            sums[side] += change
          end
        end

        diff = sums[:ce] - sums[:pe]
        return :bullish if diff.positive?
        return :bearish if diff.negative?

        :neutral
      end
    end
  end
end
