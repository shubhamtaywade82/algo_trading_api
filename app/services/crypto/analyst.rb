# frozen_string_literal: true

module Crypto
  # Turns a qualifying {Setup} into the execution plan a human reads before
  # taking the trade.
  #
  # The division of labour is the point, and it is deliberately lopsided:
  #
  #   * {SetupDetector} decides **whether** there is a trade. That stays
  #     arithmetic — reproducible, testable, and incapable of hallucinating a
  #     confluence that is not on the chart.
  #   * This class decides **how to describe taking it**. Entry, stop and
  #     targets arrive already computed and are passed to the model as fixed
  #     facts, so the worst a bad generation can do is read poorly. It cannot
  #     move a stop.
  #
  # Every failure path returns nil rather than raising, and the formatter
  # renders the alert without a plan when it does. An LLM outage must never
  # cost a setup that already cleared every gate — the levels are the alert,
  # the narrative is the garnish.
  #
  # Runs only for setups that are actually about to be sent: {AlertDispatcher}
  # calls it after the cooldown check, so a suppressed duplicate costs nothing.
  class Analyst
    # Telegram's limit is 4096 and the formatter has its own sections to fit,
    # so the plan is capped well short of it.
    MAX_CHARS = 1_200

    SYSTEM_PROMPT = <<~PROMPT
      You are the execution analyst on a crypto futures desk. A quantitative
      Smart Money Concepts / ICT scanner has already confirmed a setup and
      computed its levels. Your job is only to write the execution plan.

      Hard rules:
      - Never change, round or re-derive entry, stop or target prices. They are
        final. You may reference them; you may not replace them.
      - Never invent a price that was not given to you.
      - Never restate the full level list — the reader already has it above
        your text.
      - Do not recommend leverage or position size in currency terms; you do
        not know the account.
      - If the confluences look thin, say so plainly rather than talking the
        trade up. A hesitant plan is more useful than a confident wrong one.

      Format:
      - Plain text only. No markdown, no asterisks, no headings, no bullets
        using dashes at line start beyond the three labels below.
      - Exactly three short blocks, each on its own line, in this order:
        ENTRY: how to get in (limit into the point of interest vs. market on
        the trigger, whether to split the fill).
        INVALIDATION: what tells you the read is wrong before the stop is hit.
        MANAGEMENT: where to trail, when to take partials, what to do at TP1.
      - Under 110 words total.
    PROMPT

    def self.call(...) = new(...).call

    def initialize(setup, router: Openai::ChatRouter)
      @setup  = setup
      @router = router
    end

    # @return [String, nil] the plan, or nil when disabled or unavailable
    def call
      return nil unless Config.llm_enabled?

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      raw = @router.ask!(prompt, system: SYSTEM_PROMPT, model: Config.llm_model)
      plan = clean(raw)

      log(plan, started)
      plan
    rescue StandardError => e
      # Includes Llm::KeyRotator::Error when every key is quarantined.
      Rails.logger.error("[Crypto::Analyst] #{setup.symbol} plan unavailable: #{e.class} - #{e.message}")
      nil
    end

    private

    attr_reader :setup

    def log(plan, started)
      elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      if plan.blank?
        Rails.logger.warn("[Crypto::Analyst] #{setup.symbol} model returned nothing usable (#{elapsed}ms)")
      else
        Rails.logger.info("[Crypto::Analyst] #{setup.symbol} plan in #{elapsed}ms (#{plan.length} chars)")
      end
    end

    # --- prompt ------------------------------------------------------------

    def prompt
      [
        headline,
        levels_block,
        context_block,
        confluence_block,
        missing_block,
        'Write the execution plan.'
      ].compact.join("\n\n")
    end

    def headline
      "#{setup.symbol} — #{setup.side} setup on Binance USD-M futures.\n" \
        "Grade #{setup.grade}, confluence score #{setup.score}/100."
    end

    def levels_block
      lines = [
        "entry  #{fmt(setup.entry)}",
        "stop   #{fmt(setup.stop)}  (#{Formatting.move_percent(setup.entry, setup.stop)})",
        "tp1    #{fmt(setup.target1)}  (#{Formatting.move_percent(setup.entry, setup.target1)})"
      ]
      lines << "tp2    #{fmt(setup.target2)}  (#{Formatting.move_percent(setup.entry, setup.target2)})" if setup.target2
      lines << "risk per unit #{fmt(setup.risk)}, reward:risk to tp1 #{setup.risk_reward}"

      "Fixed levels (do not alter):\n#{lines.join("\n")}"
    end

    def context_block
      parts = []

      bias = setup.context[:bias] || {}
      unless bias.empty?
        ordered = %w[1d 4h 1h 15m 5m].filter_map { |tf| "#{tf} #{bias[tf]}" if bias.key?(tf) }
        parts << "Timeframe bias: #{ordered.join(', ')}"
      end

      parts << "Dealing range: price is in #{setup.context[:range_zone]}" if setup.context[:range_zone].present?

      if setup.poi
        parts << "Point of interest: #{setup.poi.direction} #{setup.poi.kind.to_s.tr('_', ' ')} " \
                 "#{fmt(setup.poi.bottom)}–#{fmt(setup.poi.top)}"
      end

      parts.presence&.join("\n")
    end

    def confluence_block
      return nil if setup.confluences.blank?

      "Confluences that fired:\n#{setup.confluences.map { |c| "- #{c[:label]}" }.join("\n")}"
    end

    # What did *not* line up is as informative as what did — it is the
    # difference between a setup that scraped past the threshold and one that
    # cleared it comfortably, and it is what the caveat in the plan should be
    # about.
    def missing_block
      fired = Array(setup.confluences).filter_map { |c| c[:key] }
      missing = SetupDetector::WEIGHTS.keys - fired
      return nil if missing.empty?

      "Did not fire: #{missing.map { |k| k.to_s.tr('_', ' ') }.join(', ')}"
    end

    def fmt(value) = Formatting.price(value)

    # --- response ----------------------------------------------------------

    # Ollama Cloud's default models emit reasoning, and several wrap output in
    # markdown whatever the instructions say. The Telegram message is plain
    # text on purpose (see {SetupFormatter}), so it is stripped here rather
    # than hoping the model complies.
    def clean(raw)
      text = raw.to_s.dup
      text.gsub!(%r{<think>.*?</think>}mi, '')
      text.gsub!(/```[a-z]*\n?/i, '')
      text.gsub!(/[*_`#]/, '')
      text.gsub!(/\n{3,}/, "\n\n")
      text.strip!

      truncate(text)
    end

    def truncate(text)
      return text if text.length <= MAX_CHARS

      "#{text[0, MAX_CHARS].sub(/\s\S*\z/, '')}…"
    end
  end
end
