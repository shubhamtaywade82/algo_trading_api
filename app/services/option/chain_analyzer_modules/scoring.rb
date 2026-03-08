# frozen_string_literal: true

module Option
  module ChainAnalyzerModules
    # Scoring logic for strikes in ChainAnalyzer
    module Scoring
      def score_for(opt, strategy, signal_type, signal_strength)
        base_scores = calculate_base_scores(opt, strategy)
        atm_score = calculate_atm_score(opt, signal_type)

        total = base_scores.values.sum + atm_score

        total = apply_iv_skew_adjustments(total, opt, signal_type)
        total = apply_historical_iv_check(total, opt)

        total * signal_strength
      end

      private

      def calculate_base_scores(opt, strategy)
        spread = opt[:bid_ask_spread] <= 0 ? 0.1 : opt[:bid_ask_spread]
        relative_spread = spread / opt[:last_price].to_f
        lw, mw, _tw = strategy == 'intraday' ? [0.35, 0.35, 0.3] : [0.25, 0.25, 0.5]

        {
          liquidity: liquidity_score(opt, relative_spread) * lw,
          momentum: momentum_score(opt) * mw,
          greeks: greeks_score(opt) * theta_weight,
          efficiency: efficiency_score(opt)
        }
      end

      def liquidity_score(opt, relative_spread)
        oi = [opt[:oi], 1].max
        volume = [opt[:volume], 1].max
        ((oi * volume) + opt[:volume_change].abs) / (relative_spread.nonzero? || 0.01)
      end

      def momentum_score(opt)
        score = (opt[:oi_change] / 1000.0)
        return score unless opt[:greeks][:delta].abs >= 0 && opt[:price_change].positive?

        score + opt[:price_change]
      end

      def greeks_score(opt)
        days_left = (@expiry - Time.zone.today).to_i
        theta_penalty = opt[:greeks][:theta].abs * (days_left < 3 ? 2.0 : 1.0)
        (opt[:greeks][:delta].abs * 100) + (opt[:greeks][:gamma] * 10) + (opt[:greeks][:vega] * 2) - (theta_penalty * 3)
      end

      def efficiency_score(opt)
        efficiency = opt[:price_change].zero? ? 0.0 : opt[:price_change] / opt[:last_price].to_f
        efficiency * 30
      end

      def calculate_atm_score(opt, signal_type)
        atm_strike = determine_atm_strike
        return 0 unless atm_strike

        distance = (opt[:strike_price] - atm_strike).abs
        range = atm_range_pct * @underlying_spot

        score = if distance <= (range * 0.1) then 100
                elsif distance <= (range * 0.3) then 80
                elsif distance <= (range * 0.6) then 50
                elsif distance <= (range * 1.0) then 20
                else
                  0
                end

        itm_strike?(opt[:strike_price], signal_type) ? score * 0.7 : score
      end

      def apply_iv_skew_adjustments(total, opt, signal_type)
        z = local_iv_zscore(opt[:iv], opt[:strike_price])
        adjusted = z > 1.5 ? total * 0.90 : total

        tilt = skew_tilt
        adjusted *= 1.10 if (signal_type == :ce && tilt == :call) || (signal_type == :pe && tilt == :put)

        adjusted
      end

      def apply_historical_iv_check(total, opt)
        hist_vol = historical_volatility
        return total unless hist_vol.positive?

        iv_ratio = opt[:iv] / hist_vol
        iv_ratio > 1.5 ? total * 0.9 : total
      end

      def theta_weight
        Time.zone.now.hour >= 13 ? 4.0 : 3.0
      end

      def summary_distance_threshold(atm_strike)
        return 0.0 unless atm_strike

        base_window = atm_range_pct * @underlying_spot * 2 # allow slightly wider than trading window
        step_window = (@strike_step.to_f * 3).abs

        [base_window, step_window].max
      end

      def local_iv_zscore(strike_iv, strike)
        neighbours = @option_chain[:oc].keys.map(&:to_f)
                                       .select { |s| (s - strike).abs <= 3 * 100 }
        ivs = neighbours.map do |s|
          @option_chain[:oc][format('%.6f', s)]['ce']['implied_volatility'].to_f
        end
        return 0 if ivs.empty?

        mean = ivs.sum / ivs.size
        std = Math.sqrt(ivs.sum { |v| (v - mean)**2 } / ivs.size)
        std.zero? ? 0 : (strike_iv - mean) / std
      end

      def skew_tilt
        ce_ivs = collect_side_ivs(:ce)
        pe_ivs = collect_side_ivs(:pe)

        avg_ce = ce_ivs.sum / ce_ivs.size.to_f if ce_ivs.any?
        avg_pe = pe_ivs.sum / pe_ivs.size.to_f if pe_ivs.any?

        return :call if avg_ce && avg_pe && avg_ce > avg_pe * 1.1
        return :put if avg_pe && avg_ce && avg_pe > avg_ce * 1.1

        :neutral
      end

      def collect_side_ivs(side)
        @option_chain[:oc].values.filter_map do |data|
          iv = data.dig(side.to_s, 'implied_volatility')
          iv&.to_f if iv&.to_f&.positive?
        end
      end
    end
  end
end
