# frozen_string_literal: true

module Option
  class ChainAnalyzer
    TOP_RANKED_LIMIT = 10

    attr_reader :ctx

    def initialize(option_chain, expiry:, underlying_spot:, iv_rank:, historical_data: [], strike_step: nil)
      @ctx = Components::Context.new(
        option_chain: option_chain,
        expiry: expiry,
        underlying_spot: underlying_spot,
        iv_rank: iv_rank,
        historical: historical_data,
        strike_step: strike_step
      )
    end

    # Public API stays the same
    def analyze(signal_type:, strategy_type:, signal_strength: 1.0)
      result = base_result(signal_type)

      # ---- 1) validations ---------------------------------------------------
      validations = Components::Validators.new(ctx)
      checks = validations.perform(signal_type: signal_type, strategy_type: strategy_type)
      unless checks[:failed].empty?
        result[:proceed] = false
        result[:reasons] = checks[:failed]
        result[:reason]  = checks[:failed].join('; ')
        result[:validation_details] = checks[:details]
        return result
      end

      # ---- 2) trend/momentum snapshot --------------------------------------
      result[:trend]    = ctx.trend
      result[:momentum] = ctx.momentum
      result[:adx]      = ctx.adx

      tm_check = validations.trend_momentum_gate(signal_type: signal_type)
      unless tm_check[:passed]
        result[:proceed] = false
        result[:reasons] = tm_check[:reasons]
        result[:reason]  = tm_check[:reasons].join('; ')
        result[:validation_details][:trend_momentum] = tm_check[:details]
        return result
      end

      # ---- 3) filtering + scoring ------------------------------------------
      flt     = Components::Filters.new(ctx)
      scorer  = Components::Scorer.new(ctx)
      guided  = Components::Guidance.new(ctx)

      filtered = flt.filtered_strikes(signal_type: signal_type)
      if filtered.empty?
        result[:proceed] = false
        result[:reasons] = ['No tradable strikes found']
        result[:reason]  = 'No tradable strikes found'
        result[:validation_details][:strike_selection] = guided.filter_summary(signal_type: signal_type, filtered: [])
        return result
      end

      m_boost = (ctx.momentum == :strong ? 1.15 : 1.0)
      ranked  = filtered.map do |opt|
                  opt.merge(score: scorer.score_for(opt, strategy_type, signal_type, signal_strength) * m_boost)
                end.sort_by { |o| -o[:score] }

      result[:ranked]   = ranked.first(TOP_RANKED_LIMIT)
      result[:selected] = result[:ranked].first

      result[:validation_details][:strike_selection] = guided.selection_snapshot(
        signal_type: signal_type,
        filtered: filtered,
        ranked: result[:ranked]
      )

      result
    end

    private

    def base_result(signal_type)
      {
        proceed: true,
        reason: nil,
        reasons: [],
        signal_type: signal_type,
        trend: nil,
        momentum: nil,
        adx: nil,
        selected: nil,
        ranked: [],
        ta_snapshot: ctx.ta_snapshot,
        validation_details: {}
      }
    end
  end
end
