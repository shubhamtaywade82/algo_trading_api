# frozen_string_literal: true

module Option
  module Components
    class Validators
      def initialize(ctx) = @ctx = ctx

      def perform(signal_type:, strategy_type:)
        failed  = []
        details = {}

        # IV rank range
        if @ctx.iv_rank < Context::IV_RANK_MIN || @ctx.iv_rank > Context::IV_RANK_MAX
          failed << 'IV rank outside range'
          details[:iv_rank] = { current_rank: @ctx.iv_rank, min_rank: Context::IV_RANK_MIN, max_rank: Context::IV_RANK_MAX }
        end

        # theta risk near expiry time window
        if @ctx.theta_late_entry?
          failed << 'Late entry, theta risk'
          details[:theta_risk] = {
            current_time: Time.zone.now.strftime('%H:%M'),
            expiry_date: @ctx.expiry.strftime('%Y-%m-%d'),
            hours_left: (@ctx.expiry - Time.zone.today).to_i,
            theta_avoid_hour: Context::THETA_AVOID_HOUR
          }
        end

        # ADX gate
        adx_ok = @ctx.adx ? @ctx.adx.to_f >= @ctx.adx_min : true
        unless adx_ok
          failed << "ADX below minimum value (#{@ctx.adx})"
          details[:adx] = { current_value: @ctx.adx, min_value: @ctx.adx_min }
        end

        # trend/momentum precompute for selection summary
        details[:trend]    = @ctx.trend
        details[:momentum] = @ctx.momentum

        { failed: failed, details: details }
      end

      def trend_momentum_gate(signal_type:)
        reasons = []
        details = {}

        trend    = @ctx.trend
        momentum = @ctx.momentum
        adx_ok   = @ctx.adx ? @ctx.adx.to_f >= @ctx.adx_min : true

        if trend == :neutral
          reasons << 'Trend is neutral'
          details[:trend] = { current_trend: trend, signal_type: signal_type }
        end

        if signal_type == :ce && trend == :bearish
          reasons << 'Call signal, but trend is bearish'
          details[:trend_mismatch] = { signal_type: signal_type, current_trend: trend }
        end

        if signal_type == :pe && trend == :bullish
          reasons << 'Put signal, but trend is bullish'
          details[:trend_mismatch] ||= { signal_type: signal_type, current_trend: trend }
        end

        if momentum == :flat
          reasons << 'Momentum is flat'
          details[:momentum] = { current_momentum: momentum, signal_type: signal_type }
        end

        unless adx_ok
          reasons << "ADX below minimum value (#{@ctx.adx})"
          details[:adx] = { current_value: @ctx.adx, min_value: @ctx.adx_min }
        end

        { passed: reasons.empty?, reasons: reasons, details: details }
      end
    end
  end
end
