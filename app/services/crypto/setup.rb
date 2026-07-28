# frozen_string_literal: true

module Crypto
  # A confirmed long or short setup, ready to be described to a human.
  #
  # Nothing here is persisted and nothing here places an order — a Setup is
  # the scanner's entire output, produced only when {SetupDetector} passed
  # every gate, and consumed by the formatter and the dispatcher.
  class Setup
    attr_reader :symbol, :direction, :score, :entry, :stop, :targets, :risk,
                :risk_reward, :confluences, :poi, :context, :generated_at

    def initialize(symbol:, direction:, score:, entry:, stop:, targets:, risk:,
                   risk_reward:, confluences:, poi: nil, context: {})
      @symbol       = symbol
      @direction    = direction
      @score        = score
      @entry        = entry
      @stop         = stop
      @targets      = targets
      @risk         = risk
      @risk_reward  = risk_reward
      @confluences  = confluences
      @poi          = poi
      @context      = context
      @generated_at = Time.current
    end

    def long?  = direction == :long
    def short? = direction == :short

    def side = long? ? 'LONG' : 'SHORT'

    def bias_direction = long? ? :bullish : :bearish

    def target1 = targets.first
    def target2 = targets[1]

    # Grading is for the reader, not for the gate — anything that reaches a
    # Setup already cleared the minimum score.
    def grade
      case score
      when 85..Float::INFINITY then 'A+'
      when 75...85 then 'A'
      when 65...75 then 'B'
      else 'C'
      end
    end

    # Stable identity for deduplication: same symbol, same side, same POI
    # band. Re-running the scan five minutes later on an unchanged chart
    # produces the same key, and the dispatcher stays quiet.
    def dedupe_key
      zone = poi ? "#{round_key(poi.bottom)}-#{round_key(poi.top)}" : round_key(entry)
      "#{symbol}:#{side}:#{zone}"
    end

    def to_h
      {
        symbol: symbol, side: side, score: score, grade: grade,
        entry: entry, stop: stop, targets: targets,
        risk: risk, risk_reward: risk_reward,
        confluences: confluences.pluck(:label),
        poi: poi&.to_h, context: context, generated_at: generated_at
      }
    end

    private

    # Bucketed to four significant decimals so a one-tick difference in the
    # zone edge does not read as a new setup.
    def round_key(value)
      value.to_f.round(4)
    end
  end
end
