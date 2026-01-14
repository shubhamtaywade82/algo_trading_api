# frozen_string_literal: true

module Market
  class AiTradeValidator
    ValidationError = Class.new(StandardError)

    REQUIRED_KEYS = %w[
      decision instrument side strike entry stop\ loss target risk\ reward reason
    ].freeze

    BUY_SIDES = %w[CE PE].freeze
    DECISIONS = %w[BUY AVOID].freeze
    INSTRUMENTS = %w[NIFTY BANKNIFTY SENSEX].freeze

    Result = Struct.new(
      :decision,
      :instrument,
      :side,
      :strike,
      :entry,
      :stop_loss,
      :target,
      :rr,
      :reason,
      keyword_init: true
    )

    def self.call!(ai_text, ltp:)
      parsed = parse(ai_text)
      validate!(parsed, ltp: ltp)
      build_result(parsed)
    end

    def self.parse(text)
      raise ValidationError, 'Empty AI response' if text.blank?

      lines = text.lines.map(&:strip)
      hash = {}

      lines.each do |line|
        next unless line.include?(':')

        key, value = line.split(':', 2).map(&:strip)
        next if key.blank?

        hash[key.downcase] = value.to_s.strip
      end

      hash
    end
    private_class_method :parse

    def self.validate!(h, ltp:)
      missing = REQUIRED_KEYS - h.keys
      raise ValidationError, "Missing fields: #{missing.join(', ')}" if missing.any?

      decision = h['decision']
      raise ValidationError, 'Invalid decision' unless DECISIONS.include?(decision)

      instrument = h['instrument']
      raise ValidationError, 'Invalid instrument' unless INSTRUMENTS.include?(instrument)

      raise ValidationError, 'Reason missing' if h['reason'].blank?

      return if decision == 'AVOID'

      raise ValidationError, 'Invalid side' unless BUY_SIDES.include?(h['side'])

      strike = Integer(h['strike'], exception: false)
      raise ValidationError, 'Invalid strike' unless strike&.positive?

      entry = Float(h['entry'], exception: false)
      stop_loss = Float(h['stop loss'], exception: false)
      target = Float(h['target'], exception: false)
      rr_input = Float(h['risk reward'], exception: false)

      raise ValidationError, 'Invalid prices' unless entry && stop_loss && target
      raise ValidationError, 'Risk Reward missing' unless rr_input

      raise ValidationError, 'SL >= Entry' if stop_loss >= entry
      raise ValidationError, 'Target <= Entry' if target <= entry

      rr = ((target - entry) / (entry - stop_loss)).round(2)
      raise ValidationError, "RR < 1.5 (#{rr})" if rr < 1.5

      ltp_value = Float(ltp, exception: false)
      raise ValidationError, 'Invalid LTP' unless ltp_value&.positive?

      max_allowed_entry = ltp_value * 1.05
      raise ValidationError, 'Entry too far from LTP' if entry > max_allowed_entry
    end
    private_class_method :validate!

    def self.build_result(h)
      return Result.new(decision: 'AVOID', reason: h['reason'], instrument: h['instrument']) if h['decision'] == 'AVOID'

      Result.new(
        decision: h['decision'],
        instrument: h['instrument'],
        side: h['side'],
        strike: h['strike'].to_i,
        entry: h['entry'].to_f,
        stop_loss: h['stop loss'].to_f,
        target: h['target'].to_f,
        rr: h['risk reward'].to_f,
        reason: h['reason']
      )
    end
    private_class_method :build_result
  end
end

