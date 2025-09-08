# frozen_string_literal: true

module Indicators
  class << self
    def build_supertrend(series:, period:, multiplier:)
      use_adaptive = AppSetting.fetch_bool('use_adaptive_st', default: Rails.env.production?)
      training_period   = AppSetting.fetch_int('adaptive_st_training',   default: 50)
      num_clusters      = AppSetting.fetch_int('adaptive_st_clusters',   default: 3)
      performance_alpha = AppSetting.fetch_float('adaptive_st_alpha',    default: 0.1)

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
