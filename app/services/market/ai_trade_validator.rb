# frozen_string_literal: true

module Market
  class AiTradeValidator
    ValidationError = Class.new(StandardError)

    BUY_SIDES = %w[CE PE].freeze
    DECISIONS = %w[BUY WAIT NO_TRADE].freeze
    INSTRUMENTS = %w[NIFTY BANKNIFTY SENSEX].freeze

    Result = Struct.new(
      :decision,
      :instrument,
      :reason,
      :market_bias,
      :risk_note,
      :re_evaluate_when,
      :bias,
      :no_trade_because,
      :trigger_conditions,
      :preferred_option,
      :option,
      :execution,
      :underlying_context,
      :exit_rules,
      keyword_init: true
    )

    def self.call!(ai_text, instrument_symbol:, options_snapshot: nil)
      parsed = parse(ai_text)
      validate!(parsed, instrument_symbol: instrument_symbol, options_snapshot: options_snapshot)
      build_result(parsed)
    end

    SECTION_TYPES = {
      'Option' => :hash,
      'Execution' => :hash,
      'Underlying Context' => :hash,
      'Exit Rules' => :array,
      'Re-evaluate When' => :array,
      'No Trade Because' => :array,
      'Trigger Conditions' => :array,
      'Preferred Option (If Triggered)' => :hash
    }.freeze

    REQUIRED_BY_DECISION = {
      'NO_TRADE' => ['Decision', 'Instrument', 'Market Bias', 'Reason', 'Risk Note', 'Re-evaluate When'],
      'WAIT' => ['Decision', 'Instrument', 'Bias', 'No Trade Because', 'Trigger Conditions', 'Preferred Option (If Triggered)', 'Reason'],
      'BUY' => ['Decision', 'Instrument', 'Bias', 'Option', 'Execution', 'Underlying Context', 'Exit Rules', 'Reason']
    }.freeze

    ALLOWED_BY_DECISION = {
      'NO_TRADE' => REQUIRED_BY_DECISION.fetch('NO_TRADE'),
      'WAIT' => REQUIRED_BY_DECISION.fetch('WAIT'),
      'BUY' => REQUIRED_BY_DECISION.fetch('BUY')
    }.freeze

    def self.parse(text)
      raise ValidationError, 'Empty AI response' if text.blank?

      lines = text.lines.map(&:rstrip).map(&:strip).reject(&:empty?)
      data = {}
      current_section = nil

      lines.each do |line|
        if !line.start_with?('-') && (m = line.match(/\A(?<key>[A-Za-z ()-]+):\s*(?<value>.*)\z/))
          key = m[:key]
          value = m[:value].to_s.strip

          if value.empty?
            current_section = key
            section_type = SECTION_TYPES[current_section] || :string
            data[current_section] = (section_type == :hash ? {} : [])
          else
            data[key] = value
            current_section = nil
          end

          next
        end

        next unless line.start_with?('-')

        raise ValidationError, 'List item without section header' if current_section.nil?

        payload = line.sub(/\A-\s*/, '')
        section_type = SECTION_TYPES[current_section]

        if section_type == :hash
          m = payload.match(/\A(?<k>[^:]+):\s*(?<v>.*)\z/)
          raise ValidationError, "Invalid section entry under #{current_section}" unless m

          data[current_section][m[:k].strip] = m[:v].to_s.strip
        else
          data[current_section] << payload
        end
      end

      data
    end
    private_class_method :parse

    def self.validate!(h, instrument_symbol:, options_snapshot:)
      decision = h['Decision']
      raise ValidationError, 'Missing Decision' if decision.blank?
      raise ValidationError, 'Invalid decision' unless DECISIONS.include?(decision)

      instrument = h['Instrument']
      raise ValidationError, 'Missing Instrument' if instrument.blank?
      raise ValidationError, 'Invalid instrument' unless INSTRUMENTS.include?(instrument)
      raise ValidationError, 'Instrument mismatch' unless instrument == instrument_symbol.to_s.upcase

      required = REQUIRED_BY_DECISION.fetch(decision)
      missing = required.select { |k| h[k].blank? }
      raise ValidationError, "Missing fields: #{missing.join(', ')}" if missing.any?

      allowed = ALLOWED_BY_DECISION.fetch(decision)
      extras = h.keys - allowed
      raise ValidationError, "Unexpected fields: #{extras.join(', ')}" if extras.any?

      case decision
      when 'NO_TRADE'
        validate_no_trade!(h)
      when 'WAIT'
        validate_wait!(h)
      when 'BUY'
        validate_buy!(h, options_snapshot: options_snapshot)
      end
    end
    private_class_method :validate!

    def self.validate_no_trade!(h)
      market_bias = h['Market Bias']
      raise ValidationError, 'Invalid Market Bias' unless %w[RANGE UNCLEAR].include?(market_bias)

      list = h['Re-evaluate When']
      raise ValidationError, 'Re-evaluate When must be a list' unless list.is_a?(Array) && list.any?
    end
    private_class_method :validate_no_trade!

    def self.validate_wait!(h)
      raise ValidationError, 'No Trade Because must be a list' unless h['No Trade Because'].is_a?(Array) && h['No Trade Because'].any?
      raise ValidationError, 'Trigger Conditions must be a list' unless h['Trigger Conditions'].is_a?(Array) && h['Trigger Conditions'].any?

      preferred = h['Preferred Option (If Triggered)']
      raise ValidationError, 'Preferred Option (If Triggered) must be a map' unless preferred.is_a?(Hash) && preferred.any?

      ['Type', 'Strike Zone', 'Expected Premium Zone'].each do |k|
        raise ValidationError, "Preferred Option missing #{k}" if preferred[k].blank?
      end

      # No execution pricing allowed in WAIT.
      forbidden = /\b(Entry Premium|Stop Loss Premium|Target Premium|Risk Reward)\b/i
      raise ValidationError, 'WAIT must not include execution pricing' if dump(h).match?(forbidden)
    end
    private_class_method :validate_wait!

    def self.validate_buy!(h, options_snapshot:)
      option = h['Option']
      execution = h['Execution']
      underlying = h['Underlying Context']
      exit_rules = h['Exit Rules']

      raise ValidationError, 'Option must be a map' unless option.is_a?(Hash) && option.any?
      raise ValidationError, 'Execution must be a map' unless execution.is_a?(Hash) && execution.any?
      raise ValidationError, 'Underlying Context must be a map' unless underlying.is_a?(Hash) && underlying.any?
      raise ValidationError, 'Exit Rules must be a list' unless exit_rules.is_a?(Array) && exit_rules.any?

      side = option['Type']
      raise ValidationError, 'Invalid option type' unless BUY_SIDES.include?(side)

      strike = Integer(option['Strike'], exception: false)
      raise ValidationError, 'Invalid strike' unless strike&.positive?
      raise ValidationError, 'Missing expiry' if option['Expiry'].blank?

      entry = Float(execution['Entry Premium'], exception: false)
      stop_loss = Float(execution['Stop Loss Premium'], exception: false)
      target = Float(execution['Target Premium'], exception: false)
      rr_input = Float(execution['Risk Reward'], exception: false)

      raise ValidationError, 'Invalid execution prices' unless entry && stop_loss && target && rr_input
      raise ValidationError, 'SL >= Entry' if stop_loss >= entry
      raise ValidationError, 'Target <= Entry' if target <= entry

      rr = ((target - entry) / (entry - stop_loss)).round(2)
      raise ValidationError, "RR < 1.5 (#{rr})" if rr < 1.5
      raise ValidationError, 'Risk Reward mismatch' if (rr - rr_input).abs > 0.25

      validate_underlying_context!(underlying)
      validate_exit_rules!(exit_rules)
      validate_entry_vs_snapshot!(options_snapshot, strike: strike, side: side, entry: entry)
    end
    private_class_method :validate_buy!

    def self.build_result(h)
      Result.new(
        decision: h['Decision'],
        instrument: h['Instrument'],
        market_bias: h['Market Bias'],
        risk_note: h['Risk Note'],
        re_evaluate_when: h['Re-evaluate When'],
        bias: h['Bias'],
        no_trade_because: h['No Trade Because'],
        trigger_conditions: h['Trigger Conditions'],
        preferred_option: h['Preferred Option (If Triggered)'],
        option: h['Option'],
        execution: h['Execution'],
        underlying_context: h['Underlying Context'],
        exit_rules: h['Exit Rules'],
        reason: h['Reason']
      )
    end
    private_class_method :build_result

    def self.validate_underlying_context!(underlying)
      inv = underlying['Invalidation Below'] || underlying['Invalidation Above']
      raise ValidationError, 'Missing underlying invalidation level' if inv.blank?
      raise ValidationError, 'Invalidation must include a numeric level' unless inv.to_s.match?(/\d/)

      spot_ref = underlying['Spot Above'] || underlying['Spot Below']
      raise ValidationError, 'Missing spot reference level' if spot_ref.blank?
      raise ValidationError, 'Spot reference must include a numeric level' unless spot_ref.to_s.match?(/\d/)
    end
    private_class_method :validate_underlying_context!

    def self.validate_exit_rules!(rules)
      underlying_rule = rules.any? do |r|
        r.match?(/\bSpot\b.*\b(below|above)\b.*\d/i) || r.match?(/\bSpot closes\b.*\b(below|above)\b.*\d/i)
      end
      raise ValidationError, 'Exit Rules must include an underlying condition' unless underlying_rule
    end
    private_class_method :validate_exit_rules!

    def self.validate_entry_vs_snapshot!(options_snapshot, strike:, side:, entry:)
      raise ValidationError, 'Missing option chain snapshot' if options_snapshot.blank?

      node = Array(options_snapshot.values).find { |row| row.is_a?(Hash) && row[:strike].to_i == strike }
      raise ValidationError, 'Strike not present in option snapshot' unless node

      side_key = side == 'CE' ? :call : :put
      contract = node[side_key] || {}

      ltp = contract['last_price'] || contract[:last_price]
      ask = contract['top_ask_price'] || contract[:top_ask_price]

      ref = Float(ask || ltp, exception: false)
      raise ValidationError, 'Option premium reference missing' unless ref&.positive?

      max_allowed = (ref * 1.05).round(2)
      raise ValidationError, 'Entry premium too far from LTP/ask' if entry > max_allowed
    end
    private_class_method :validate_entry_vs_snapshot!

    def self.dump(h)
      h.to_s
    end
    private_class_method :dump
  end
end

