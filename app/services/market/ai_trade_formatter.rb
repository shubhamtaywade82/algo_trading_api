# frozen_string_literal: true

module Market
  class AiTradeFormatter
    def self.format(result)
      case result.decision.to_s.upcase
      when 'BUY' then format_buy(result)
      when 'WAIT' then format_wait(result)
      else format_no_trade(result)
      end
    end

    def self.format_buy(result)
      spot_ref = result.underlying_context['Spot Above'] || result.underlying_context['Spot Below']
      invalidation = result.underlying_context['Invalidation Below'] || result.underlying_context['Invalidation Above']

      spot_ref_label = result.underlying_context.key?('Spot Below') ? 'Spot Below' : 'Spot Above'
      invalidation_label = result.underlying_context.key?('Invalidation Above') ? 'Invalidation Above' : 'Invalidation Below'

      <<~MSG.strip
        Decision: BUY
        Instrument: #{result.instrument}
        Bias: #{result.bias}

        Option:
        - Type: #{result.option['Type']}
        - Strike: #{result.option['Strike']}
        - Expiry: #{result.option['Expiry']}

        Execution:
        - Entry Premium: #{result.execution['Entry Premium']}
        - Stop Loss Premium: #{result.execution['Stop Loss Premium']}
        - Target Premium: #{result.execution['Target Premium']}
        - Risk Reward: #{result.execution['Risk Reward']}

        Underlying Context:
        - #{spot_ref_label}: #{spot_ref}
        - #{invalidation_label}: #{invalidation}

        Exit Rules:
        - #{result.exit_rules.join("\n- ")}

        Reason: #{result.reason}
      MSG
    end
    private_class_method :format_buy

    def self.format_wait(result)
      <<~MSG.strip
        Decision: WAIT
        Instrument: #{result.instrument}
        Bias: #{result.bias}
        No Trade Because:
        - #{result.no_trade_because.join("\n- ")}
        Trigger Conditions:
        - #{result.trigger_conditions.join("\n- ")}
        Preferred Option (If Triggered):
        - Type: #{result.preferred_option['Type']}
        - Strike Zone: #{result.preferred_option['Strike Zone']}
        - Expected Premium Zone: #{result.preferred_option['Expected Premium Zone']}
        Reason: #{result.reason}
      MSG
    end
    private_class_method :format_wait

    def self.format_no_trade(result)
      <<~MSG.strip
        Decision: NO_TRADE
        Instrument: #{result.instrument}
        Market Bias: #{result.market_bias || 'UNCLEAR'}
        Reason: #{result.reason}
        Risk Note: #{result.risk_note || 'No edge for options buying'}
        Re-evaluate When:
        - #{Array(result.re_evaluate_when).join("\n- ")}
      MSG
    end
    private_class_method :format_no_trade
  end
end

