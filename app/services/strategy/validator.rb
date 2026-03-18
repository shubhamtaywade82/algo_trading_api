# frozen_string_literal: true

class Strategy
  # Validates an AI-generated trade proposal before it enters the execution engine.
  #
  # This is the deterministic gate between the AI layer and order execution.
  # Pure function — no database writes, no API calls, no side effects.
  #
  # Usage:
  #   proposal = AI::TradeBrain.propose(symbol: "NIFTY")[:proposal]
  #   if Strategy::Validator.valid?(proposal)
  #     Orders::Executor.place(proposal)
  #   end
  #
  # Detailed errors:
  #   result = Strategy::Validator.validate(proposal)
  #   result[:valid]   # => false
  #   result[:errors]  # => ["Stop loss missing", "Risk not approved"]
  class Validator
    REQUIRED_FIELDS     = %i[symbol direction strike entry_price stop_loss target].freeze
    MIN_CONFIDENCE      = 0.60
    MIN_RISK_REWARD     = 1.5
    VALID_DIRECTIONS    = %w[CE PE].freeze
    VALID_PRODUCTS      = %w[INTRADAY MARGIN CNC].freeze
    MAX_ENTRY_PRICE     = 10_000.0   # sanity cap for option premiums
    MIN_ENTRY_PRICE     = 0.50       # illiquid option floor

    # @param proposal [Hash]   trade proposal from TradeBrain (symbol-keyed or string-keyed)
    # @return [Boolean]
    def self.valid?(proposal)
      validate(proposal)[:valid]
    end

    # @param proposal [Hash]
    # @return [Hash]  { valid: Boolean, errors: Array<String>, warnings: Array<String> }
    def self.validate(proposal)
      new(proposal).validate
    end

    def initialize(proposal)
      @p = proposal.with_indifferent_access rescue proposal.to_h.with_indifferent_access
    end

    def validate
      errors   = []
      warnings = []

      errors.concat(check_required_fields)
      errors.concat(check_direction)
      errors.concat(check_numeric_fields)
      errors.concat(check_risk_reward)
      errors.concat(check_confidence)
      errors.concat(check_risk_approval)
      errors.concat(check_market_hours)

      warnings.concat(check_warnings)

      { valid: errors.empty?, errors: errors, warnings: warnings }
    end

    private

    def check_required_fields
      REQUIRED_FIELDS.filter_map do |field|
        "#{field} is missing or blank" if @p[field].blank?
      end
    end

    def check_direction
      dir = @p[:direction].to_s.upcase
      return [] if VALID_DIRECTIONS.include?(dir)

      ["direction must be CE or PE, got: '#{dir}'"]
    end

    def check_numeric_fields
      errors = []

      entry = @p[:entry_price].to_f
      sl    = @p[:stop_loss].to_f
      tgt   = @p[:target].to_f
      qty   = @p[:quantity].to_i

      errors << "entry_price must be > #{MIN_ENTRY_PRICE}"   if entry <= MIN_ENTRY_PRICE
      errors << "entry_price must be < #{MAX_ENTRY_PRICE}"   if entry >= MAX_ENTRY_PRICE
      errors << 'stop_loss must be less than entry_price'    if sl.positive? && sl >= entry
      errors << 'target must be greater than entry_price'    if tgt.positive? && tgt <= entry
      errors << 'quantity must be a positive integer'        if qty <= 0
      errors << 'strike must be a positive number'           if @p[:strike].to_i <= 0

      errors
    end

    def check_risk_reward
      entry = @p[:entry_price].to_f
      sl    = @p[:stop_loss].to_f
      tgt   = @p[:target].to_f

      return [] if entry.zero? || sl.zero? || tgt.zero?

      risk   = entry - sl
      reward = tgt - entry

      return [] if risk <= 0

      rr = reward / risk
      if rr < MIN_RISK_REWARD
        ["risk-reward #{rr.round(2)} is below minimum #{MIN_RISK_REWARD}"]
      else
        []
      end
    end

    def check_confidence
      confidence = @p[:confidence].to_f
      return [] if confidence.zero?  # not provided — skip

      confidence >= MIN_CONFIDENCE ? [] : ["confidence #{confidence} is below minimum #{MIN_CONFIDENCE}"]
    end

    def check_risk_approval
      # If the risk agent explicitly rejected the trade, block it
      return [] unless @p.key?(:risk_approved)

      @p[:risk_approved] == true ? [] : ['Risk agent did not approve this trade']
    end

    def check_market_hours
      # Only warn, not reject — the execution layer handles this more precisely
      []
    end

    def check_warnings
      warnings = []

      product = @p[:product].to_s.upcase
      warnings << "Unrecognized product type: #{product}" unless product.blank? || VALID_PRODUCTS.include?(product)

      expiry = @p[:expiry]
      if expiry.present?
        begin
          exp_date = Date.parse(expiry.to_s)
          warnings << 'Expiry is in the past' if exp_date < Time.zone.today
        rescue ArgumentError
          warnings << "Could not parse expiry date: #{expiry}"
        end
      end

      rr = @p[:risk_reward].to_f
      warnings << "risk_reward (#{rr.round(2)}) is high (>5) — verify targets" if rr > 5.0

      warnings
    end
  end
end
