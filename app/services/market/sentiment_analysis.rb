# frozen_string_literal: true

module Market
  class SentimentAnalysis
    DEFAULT_STRATEGY_TYPE = 'intraday'

    def self.call(option_chain:, expiry:, spot:, iv_rank:, historical_data: [], strategy_type: DEFAULT_STRATEGY_TYPE)
      new(option_chain:, expiry:, spot:, iv_rank:, historical_data:, strategy_type:).call
    end

    def initialize(option_chain:, expiry:, spot:, iv_rank:, historical_data:, strategy_type:)
      @option_chain    = option_chain.with_indifferent_access
      @expiry          = expiry
      @spot            = spot.to_f
      @iv_rank         = iv_rank.to_f
      @historical_data = historical_data || []
      @strategy_type   = strategy_type.presence || DEFAULT_STRATEGY_TYPE
    end

    def call
      analyzer     = build_analyzer
      call_result  = analyzer.analyze(signal_type: :ce, strategy_type: @strategy_type)
      put_result   = analyzer.analyze(signal_type: :pe, strategy_type: @strategy_type)
      ta_snapshot  = analyzer.ta ? analyzer.ta.to_h : {}

      ce_strength = strike_strength(call_result)
      pe_strength = strike_strength(put_result)

      preferred_signal = pick_preferred_signal(call_result, put_result, ce_strength, pe_strength)
      bias =
        case preferred_signal
        when :ce then :bullish
        when :pe then :bearish
        else :neutral
        end

      confidence = compute_confidence(ce_strength, pe_strength)
      trend = call_result[:trend] || put_result[:trend]

      {
        bias: bias,
        preferred_signal: preferred_signal,
        confidence: confidence,
        trend: trend,
        iv_rank: @iv_rank,
        strengths: { ce: ce_strength, pe: pe_strength },
        ta_snapshot: ta_snapshot,
        call_analysis: call_result,
        put_analysis: put_result
      }
    end

    private

    def build_analyzer
      Option::ChainAnalyzer.new(
        @option_chain,
        expiry: @expiry,
        underlying_spot: @spot,
        iv_rank: @iv_rank,
        historical_data: @historical_data
      )
    end

    def strike_strength(result)
      return 0.0 unless result
      return 0.0 unless result[:selected].is_a?(Hash)

      result[:selected][:score].to_f
    end

    def pick_preferred_signal(call_result, put_result, ce_strength, pe_strength)
      call_ok = call_result[:proceed]
      put_ok  = put_result[:proceed]

      return :ce if call_ok && !put_ok
      return :pe if put_ok && !call_ok

      return nil unless call_ok || put_ok

      return :ce if ce_strength > pe_strength
      return :pe if pe_strength > ce_strength

      nil
    end

    def compute_confidence(ce_strength, pe_strength)
      max_strength = [ce_strength, pe_strength].max
      return 0.0 if max_strength.zero?

      diff = (ce_strength - pe_strength).abs
      (diff / max_strength.to_f).round(2)
    end
  end
end
