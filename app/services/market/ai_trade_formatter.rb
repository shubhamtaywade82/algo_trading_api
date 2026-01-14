# frozen_string_literal: true

module Market
  class AiTradeFormatter
    def self.format(result, expiry: nil)
      return format_avoid(result) if result.decision.to_s.upcase == 'AVOID'

      format_buy(result, expiry: expiry)
    end

    def self.format_buy(result, expiry:)
      expiry_text = expiry.present? ? " (exp #{expiry})" : ''

      <<~MSG.strip
        📊 #{result.instrument} OPTIONS BUYING#{expiry_text}

        BUY #{result.instrument} #{result.strike} #{result.side}
        Entry: #{result.entry}
        SL: #{result.stop_loss}
        Target: #{result.target}
        R:R: #{result.rr}

        Reason:
        #{result.reason}
      MSG
    end
    private_class_method :format_buy

    def self.format_avoid(result)
      <<~MSG.strip
        🚫 NO TRADE (#{result.instrument})

        Reason:
        #{result.reason}
      MSG
    end
    private_class_method :format_avoid
  end
end

