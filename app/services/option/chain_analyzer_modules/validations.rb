# frozen_string_literal: true

module Option
  module ChainAnalyzerModules
    # Validation checks for ChainAnalyzer
    module Validations
      def perform_validation_checks(signal_type, _strategy_type)
        checks = {
          failed: [],
          details: {}
        }

        # 1️⃣  IV Rank Check
        if iv_rank_outside_range?
          checks[:failed] << 'IV rank outside range'
          checks[:details][:iv_rank] = {
            current_rank: @iv_rank,
            min_rank: ChainAnalyzer::IV_RANK_MIN,
            max_rank: ChainAnalyzer::IV_RANK_MAX
          }
        end

        # 2️⃣  Theta Risk Check
        if discourage_late_entry_due_to_theta?
          checks[:failed] << 'Late entry, theta risk'
          checks[:details][:theta_risk] = {
            current_time: Time.zone.now.strftime('%H:%M'),
            expiry_date: @expiry.strftime('%Y-%m-%d'),
            hours_left: (@expiry - Time.zone.today).to_i,
            theta_avoid_hour: ChainAnalyzer::THETA_AVOID_HOUR
          }
        end

        # 3️⃣  ADX Check
        adx_ok = ta ? ta.adx.to_f >= ChainAnalyzer::MIN_ADX_VALUE : true
        unless adx_ok
          checks[:failed] << "ADX below minimum value (#{ta&.adx})"
          checks[:details][:adx] = {
            current_value: ta&.adx,
            min_value: ChainAnalyzer::MIN_ADX_VALUE
          }
        end

        # 4️⃣  Trend Confirmation Check
        trend = ta ? ta.bias.to_sym : intraday_trend
        momentum = ta ? ta.momentum.to_sym : :flat
        trend_momentum_check = check_trend_momentum(trend, momentum, adx_ok, signal_type)
        unless trend_momentum_check[:passed]
          checks[:failed] << trend_momentum_check[:reasons].join('; ')
          checks[:details][:trend_momentum] = trend_momentum_check[:details]
        end

        checks
      end

      def check_trend_momentum(trend, momentum, adx_ok, signal_type)
        reasons = []
        details = {}

        if trend == :neutral
          reasons << 'Trend is neutral'
          details[:trend] = {
            current_trend: trend,
            signal_type: signal_type
          }
        end

        if signal_type == :ce && trend == :bearish
          reasons << 'Call signal, but trend is bearish'
          details[:trend_mismatch] = {
            signal_type: signal_type,
            current_trend: trend
          }
        end

        if signal_type == :pe && trend == :bullish
          reasons << 'Put signal, but trend is bullish'
          details[:trend_mismatch] = {
            signal_type: signal_type,
            current_trend: trend
          }
        end

        if momentum == :flat
          reasons << 'Momentum is flat'
          details[:momentum] = {
            current_momentum: momentum,
            signal_type: signal_type
          }
        end

        if adx_ok == false
          reasons << "ADX below minimum value (#{ta&.adx})"
          details[:adx] = {
            current_value: ta&.adx,
            min_value: ChainAnalyzer::MIN_ADX_VALUE
          }
        end

        {
          passed: reasons.empty?,
          reasons: reasons,
          details: details
        }
      end

      def trend_confirms?(trend, signal_type)
        return true if trend == :neutral

        (trend == :bullish && signal_type == :ce) || (trend == :bearish && signal_type == :pe)
      end

      def iv_rank_outside_range?
        @iv_rank < ChainAnalyzer::IV_RANK_MIN || @iv_rank > ChainAnalyzer::IV_RANK_MAX
      end

      def discourage_late_entry_due_to_theta?
        now = Time.zone.now
        expiry_today = @expiry == now.to_date
        current_hour = now.hour + (now.min / 60.0)
        expiry_today && current_hour > ChainAnalyzer::THETA_AVOID_HOUR
      end
    end
  end
end
