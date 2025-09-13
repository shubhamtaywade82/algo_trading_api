# frozen_string_literal: true

module Indicators
  class << self
    def build_supertrend(series:, period:, multiplier:)
      use_adaptive = ENV.fetch('USE_ADAPTIVE_ST', Rails.env.production? ? 'true' : 'false') == 'true'
      training_period   = ENV.fetch('ADAPTIVE_ST_TRAINING', '50').to_i
      num_clusters      = ENV.fetch('ADAPTIVE_ST_CLUSTERS', '3').to_i
      performance_alpha = ENV.fetch('ADAPTIVE_ST_ALPHA', '0.1').to_f

      klass = use_adaptive ? Indicators::AdaptiveSupertrend : Indicators::Supertrend

      log_choice(klass, training_period, num_clusters, performance_alpha)

      if use_adaptive
        klass.new(
          series: series,
          period: period,
          base_multiplier: multiplier,
          training_period: training_period,
          num_clusters: num_clusters,
          performance_alpha: performance_alpha
        ).call
      else
        klass.new(series: series, period: period, multiplier: multiplier).call
      end
    end

    private

    def log_choice(klass, training_period, num_clusters, performance_alpha)
      return if @logged

      if klass == Indicators::AdaptiveSupertrend
        Rails.logger.info(
          "[Indicators] AdaptiveSupertrend active (training=#{training_period}, clusters=#{num_clusters}, alpha=#{performance_alpha})"
        )
      else
        Rails.logger.info('[Indicators] Using classic Supertrend')
      end
      @logged = true
    end
  end
end
