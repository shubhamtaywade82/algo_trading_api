# frozen_string_literal: true

module AlertProcessors
  # Builds a human-readable skip reason from the chain analyzer result.
  class IndexSkipReasonBuilder
    def self.build(result)
      reasons = result[:reasons] || [result[:reason]]
      main_reason = reasons.join('; ')
      details = format_validation_details(result[:validation_details] || {})
      details.any? ? "#{main_reason} | Details: #{details.join(' | ')}" : main_reason
    end

    def self.format_validation_details(validation_details)
      details = []
      details << format_iv_rank(validation_details[:iv_rank]) if validation_details[:iv_rank]
      details << format_theta_risk(validation_details[:theta_risk]) if validation_details[:theta_risk]
      details << format_adx(validation_details[:adx]) if validation_details[:adx]
      details.concat(format_trend_momentum(validation_details[:trend_momentum])) if validation_details[:trend_momentum]
      details << format_strike_selection(validation_details[:strike_selection]) if validation_details[:strike_selection]
      details.compact
    end

    def self.format_iv_rank(iv_info)
      "IV Rank: #{iv_info[:current_rank]&.round(3)} (Range: #{iv_info[:min_rank]}-#{iv_info[:max_rank]})"
    end

    def self.format_theta_risk(theta_info)
      "Theta Risk: #{theta_info[:current_time]} (Expiry: #{theta_info[:expiry_date]}, Hours left: #{theta_info[:hours_left]})"
    end

    def self.format_adx(adx_info)
      "ADX: #{adx_info[:current_value]&.round(2)} (Min: #{adx_info[:min_value]})"
    end

    def self.format_trend_momentum(tm_info)
      parts = []
      parts << "Trend: #{tm_info[:trend][:current_trend]} (Signal: #{tm_info[:trend][:signal_type]})" if tm_info[:trend]
      parts << "Momentum: #{tm_info[:momentum][:current_momentum]} (Signal: #{tm_info[:momentum][:signal_type]})" if tm_info[:momentum]
      parts << "Trend Mismatch: #{tm_info[:trend_mismatch][:signal_type]} vs #{tm_info[:trend_mismatch][:current_trend]}" if tm_info[:trend_mismatch]
      parts
    end

    def self.format_strike_selection(ss_info)
      parts = ["Strikes: #{ss_info[:filtered_count]}/#{ss_info[:total_strikes]} passed filters"]
      if ss_info[:strike_guidance]&.dig(:recommended_strikes)&.any?
        guidance = ss_info[:strike_guidance]
        parts << "Recommended: #{Array(guidance[:recommended_strikes]).join(', ')}"
        parts << "Explanation: #{guidance[:explanation]}" if guidance[:explanation].present?
      end
      if ss_info[:filters_applied]&.any?
        formatted = Array(ss_info[:filters_applied]).map do |filter|
          filter.is_a?(Hash) ? "#{filter[:strike_price]} (#{Array(filter[:reasons]).join(', ')})" : filter
        end
        parts << "Filter Details: #{formatted.join('; ')}"
      end
      parts.join(' | ')
    end
  end
end
