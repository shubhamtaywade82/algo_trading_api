# frozen_string_literal: true

module Option
  # Analyzes option chains to find the best trading opportunities
  # by composing various filtering, validation, scoring, and TA modules.
  class ChainAnalyzer
    include ChainAnalyzerModules::TechnicalAnalysis
    include ChainAnalyzerModules::Validations
    include ChainAnalyzerModules::StrikeFiltering
    include ChainAnalyzerModules::Scoring

    IV_RANK_MIN       = 0.00
    IV_RANK_MAX       = 0.80
    BASE_ATM_RANGE_PCT = 0.01 # fallback minimum range
    THETA_AVOID_HOUR = 14.5 # 2:30 PM as float
    MIN_ADX_VALUE = Rails.env.production? ? 20 : 10

    TOP_RANKED_LIMIT = 10

    attr_reader :option_chain, :expiry, :underlying_spot, :historical_data, :iv_rank, :ta, :strike_step

    def self.estimate_iv_rank(option_chain)
      return 0.5 unless option_chain.respond_to?(:[]) && option_chain.present?

      chain = option_chain.with_indifferent_access
      oc     = chain[:oc]
      return 0.5 if oc.blank?

      spot    = chain[:last_price].to_f
      strikes = oc.keys.map(&:to_f)
      return 0.5 if strikes.empty?

      atm      = strikes.min_by { |s| (s - spot).abs }
      atm_key  = format('%.6f', atm)
      fetch_iv = ->(side) { oc.dig(atm_key, side, 'implied_volatility').to_f }

      ce_iv = fetch_iv.call('ce')
      pe_iv = fetch_iv.call('pe')
      candidate_ivs = [ce_iv, pe_iv].reject(&:zero?)
      current_iv = if candidate_ivs.any?
                     candidate_ivs.sum / candidate_ivs.size
                   else
                     0.0
                   end

      all_ivs = oc.values.flat_map do |row|
        %w[ce pe].map { |side| row.dig(side, 'implied_volatility').to_f }
      end.reject(&:zero?)

      return 0.5 if all_ivs.size < 2 || all_ivs.max == all_ivs.min

      current_iv = all_ivs.sum / all_ivs.size if current_iv.zero?

      ((current_iv - all_ivs.min) / (all_ivs.max - all_ivs.min)).clamp(0.0, 1.0).round(2)
    rescue StandardError
      0.5
    end

    def initialize(option_chain, expiry:, underlying_spot:, iv_rank:, historical_data: [], strike_step: nil)
      @option_chain     = option_chain.with_indifferent_access
      @expiry           = Date.parse(expiry.to_s)
      @underlying_spot  = underlying_spot.to_f
      @iv_rank          = iv_rank.to_f
      @historical_data  = historical_data || []
      @ta = build_ta_snapshot

      @strike_step = strike_step || infer_strike_step
      Rails.logger.debug { "Analyzing Options for #{expiry}" }
      raise ArgumentError, 'Option Chain is missing or empty!' if @option_chain[:oc].blank?
    end

    def analyze(signal_type:, strategy_type:, signal_strength: 1.0)
      result = {
        proceed: true,
        reason: nil,
        reasons: [],
        signal_type: signal_type,
        trend: nil,
        momentum: nil,
        adx: nil,
        selected: nil,
        ranked: [],
        ta_snapshot: ta ? ta.to_h : {},
        validation_details: {}
      }

      validation_checks = perform_validation_checks(signal_type, strategy_type)

      if validation_checks[:failed].any?
        result[:proceed] = false
        result[:reasons] = validation_checks[:failed]
        result[:reason] = validation_checks[:failed].join('; ')
        result[:validation_details] = validation_checks[:details]
        return result
      end

      result[:trend]    = ta ? ta.bias.to_sym      : intraday_trend
      result[:momentum] = ta ? ta.momentum.to_sym  : :flat
      result[:adx]      = ta&.adx
      adx_ok            = ta ? ta.adx.to_f >= MIN_ADX_VALUE : true

      trend_momentum_check = check_trend_momentum(result[:trend], result[:momentum], adx_ok, signal_type)
      unless trend_momentum_check[:passed]
        result[:proceed] = false
        result[:reasons] = trend_momentum_check[:reasons]
        result[:reason] = trend_momentum_check[:reasons].join('; ')
        result[:validation_details][:trend_momentum] = trend_momentum_check[:details]
        return result
      end

      if result[:proceed]
        filtered = gather_filtered_strikes(signal_type)

        if filtered.empty?
          result[:proceed] = false
          result[:reasons] = ['No tradable strikes found']
          result[:reason] = 'No tradable strikes found'
          result[:validation_details][:strike_selection] = get_strike_filter_summary(signal_type)
        else
          m_boost = result[:momentum] == :strong ? 1.15 : 1.0
          ranked  = filtered.map do |opt|
                      score = score_for(opt, strategy_type, signal_type, signal_strength) * m_boost
                      opt.merge(score: score)
                    end.sort_by { |o| -o[:score] }

          result[:ranked]   = ranked.first(TOP_RANKED_LIMIT)
          result[:selected] = result[:ranked].first

          result[:validation_details][:strike_selection] = {
            total_strikes: @option_chain[:oc].keys.size,
            filtered_count: filtered.size,
            ranked_count: result[:ranked].size,
            top_score: result[:selected]&.dig(:score)&.round(2),
            filters_applied: get_strike_filter_summary(signal_type),
            strike_guidance: get_strike_selection_guidance(signal_type)
          }
        end
      end

      result
    end

    def current_trend
      intraday_trend
    end
    alias trend current_trend

    private

    def oc_strikes
      @oc_strikes ||= @option_chain[:oc].keys.map(&:to_f).sort
    end

    def infer_strike_step
      diffs = oc_strikes.each_cons(2).map { |a, b| (b - a).abs }.reject(&:zero?)
      step  = diffs.group_by(&:round).max_by { |_k, v| v.size }&.first&.to_f
      return step if step&.positive?

      50.0
    end

    def nearest_grid(strike)
      oc_strikes.min_by { |s| (s - strike).abs }
    end

    def snap_to_grid(strike)
      return nil if oc_strikes.empty?

      atm = determine_atm_strike
      return oc_strikes.first unless atm

      delta  = strike - atm
      steps  = (delta / @strike_step.to_f).round
      target = atm + (steps * @strike_step.to_f)
      oc_strikes.min_by { |s| (s - target).abs }
    end

    def determine_atm_strike
      return nil if oc_strikes.empty?

      spot = (@option_chain[:last_price] || @underlying_spot).to_f
      oc_strikes.min_by { |s| (s - spot).abs }
    end
  end
end
