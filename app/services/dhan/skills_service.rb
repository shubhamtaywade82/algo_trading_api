# frozen_string_literal: true

module Dhan
  # Facade over the DhanHQ SDK's builtin skill pack (11 skills as of 3.2.1).
  #
  # Most skills are analytical: they read the option chain and build a multi-leg
  # *intent* (iron condor, straddle, covered call, ...) without sending
  # anything. Two of them — `square_off_all` and `square_off_position` — are
  # tagged `risk "destructive_write"` and call `Position.exit_all!` directly,
  # which would bypass `Orders::Gateway` and this app's PLACE_ORDER gate.
  #
  # This service keeps the analytical skills freely available while holding the
  # destructive ones to the same switches as every other order path here, and
  # returns the same structured blocked result the gateway does.
  class SkillsService < ApplicationService
    # Risk levels the SDK assigns to skills that mutate broker state.
    WRITE_RISK_LEVELS = %w[write destructive_write].freeze

    class << self
      # @return [Array<Hash>] skill metadata, annotated with write/permitted flags
      def catalogue
        registry.list.map do |skill|
          klass = registry.find(skill[:name])
          skill.merge(
            risk: risk_for(klass),
            scope: scope_for(klass),
            write: write?(klass),
            permitted: !write?(klass) || placement_enabled?
          )
        end
      end

      # @return [Array<String>] names of every registered skill
      delegate :names, to: :registry

      # Runs a skill by name.
      #
      # Analytical skills run directly. Destructive ones require both
      # PLACE_ORDER and LIVE_TRADING, matching Orders::Gateway.
      #
      # Accepts skill parameters either as a hash or as loose keywords, so an
      # LLM tool call that splats its arguments works the same as
      # `call("iron_condor", { symbol: "NIFTY" })`.
      #
      # @param name [String] skill name, e.g. "iron_condor"
      # @param args [Hash] skill parameters
      # @param source [String, nil] caller identifier for logs
      # @return [Hash] the skill context, or a blocked/error result
      def call(name, args = {}, source: nil, **extra)
        args = args.to_h.symbolize_keys.merge(extra)
        klass = registry.find(name)

        return blocked_result(name, source: source) if write?(klass) && !placement_enabled?

        Rails.logger.info("[Dhan::SkillsService] running skill=#{name} write=#{write?(klass)}#{source_suffix(source)}")
        { skill: name, ok: true, result: registry.call(name, args) }
      rescue KeyError => e
        { skill: name, ok: false, error: 'unknown_skill', message: e.message }
      rescue DhanHQ::RiskViolation => e
        { skill: name, ok: false, error: 'risk_violation', message: e.message }
      rescue StandardError => e
        Rails.logger.error("[Dhan::SkillsService] skill=#{name} failed: #{e.class} - #{e.message}")
        { skill: name, ok: false, error: 'skill_failed', message: e.message }
      end

      # @return [Boolean] whether a named skill mutates broker state
      def write_skill?(name)
        write?(registry.find(name))
      rescue KeyError
        false
      end

      private

      def registry
        @registry ||= begin
          DhanHQ::Skills::Registry.load_builtins
          DhanHQ::Skills::Registry
        end
      end

      def write?(klass)
        WRITE_RISK_LEVELS.include?(risk_for(klass).to_s) ||
          scope_for(klass).to_s.include?('write')
      end

      def risk_for(klass)
        klass.respond_to?(:risk) ? klass.risk : nil
      end

      def scope_for(klass)
        klass.respond_to?(:scope) ? klass.scope : nil
      end

      def placement_enabled?
        Orders::Gateway.place_order_enabled?(logger: nil)
      end

      def blocked_result(name, source: nil)
        Rails.logger.warn("[Dhan::SkillsService] blocked destructive skill=#{name}#{source_suffix(source)}")
        {
          skill: name,
          ok: false,
          blocked: true,
          dry_run: true,
          message: 'Destructive skill blocked; PLACE_ORDER and LIVE_TRADING must both be true.'
        }
      end

      def source_suffix(source)
        source.present? ? " (source=#{source})" : ''
      end
    end
  end
end
