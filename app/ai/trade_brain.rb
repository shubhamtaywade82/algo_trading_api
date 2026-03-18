# frozen_string_literal: true

module AI
  # TradeBrain — public façade for the AI agent cluster.
  #
  # Single entry point into the orchestration layer. Runners return
  # Agents::RunResult objects (from the ai-agents gem) with:
  #   result.output   → final text from the last active agent
  #   result.context  → serialisable conversation state for multi-turn sessions
  #
  # Critical boundary: TradeBrain produces PROPOSALS. It never executes orders.
  # Execution always goes through the deterministic Strategy::Validator → Orders::Executor pipeline.
  #
  # Usage:
  #   result = AI::TradeBrain.analyze("NIFTY")
  #   puts result.output
  #
  #   result   = AI::TradeBrain.propose(symbol: "NIFTY")
  #   proposal = result[:proposal]
  #   Orders::Executor.place(proposal) if Strategy::Validator.valid?(proposal)
  #
  #   result = AI::TradeBrain.ask("Why did trade #214 exit early?")
  #   puts result.output
  module TradeBrain
    module_function

    # Run the full market analysis pipeline for a symbol.
    #
    # @param symbol  [String]  NSE index symbol, e.g. "NIFTY"
    # @param candle  [String]  timeframe, e.g. "15m"
    # @param context [Hash]    optional prior conversation context (for multi-turn)
    # @return [Agents::RunResult]  result.output = analysis text, result.context = state
    def analyze(symbol, candle: '15m', context: nil)
      input = "Analyze #{symbol} market structure and options flow for the current session. " \
              "Use #{candle} candle data."

      result = AI::Runners::MarketRunner.run(input, context: context || {})
      Rails.logger.info "[TradeBrain] analyze(#{symbol}) complete"
      result
    end

    # Generate a trade proposal via the full agent pipeline.
    #
    # The returned :proposal hash must pass Strategy::Validator.valid? before execution.
    #
    # @param symbol    [String]  NSE index symbol
    # @param direction [String]  optional hint: "CE", "PE", or nil (auto)
    # @param context   [Hash]    optional prior conversation context
    # @return [Hash]   { result:, proposal:, validation: }
    def propose(symbol:, direction: nil, context: nil)
      dir_hint = direction ? " Preferred direction: #{direction}." : ''
      input    = "Generate a concrete options trade setup for #{symbol}.#{dir_hint} " \
                 "Include specific strike, entry, stop-loss, and target."

      result   = AI::Runners::TradeRunner.run(input, context: context || {})
      proposal = AI::Runners::TradeRunner.extract_proposal(result.output)

      Rails.logger.info "[TradeBrain] propose(#{symbol}) → proposal=#{proposal.inspect}"

      {
        result:     result,
        output:     result.output,
        context:    result.context,
        proposal:   proposal,
        validation: proposal ? Strategy::Validator.validate(proposal) : nil
      }
    end

    # Analyze all current positions for risk and exit recommendations.
    #
    # @param context [Hash]  optional prior conversation context
    # @return [Agents::RunResult]
    def review_positions(context: nil)
      result = AI::Runners::OperatorRunner.run(
        "Review all current open positions. Assess P&L, risk level, " \
        "and flag any positions that should be considered for exit.",
        context: context || {}
      )

      Rails.logger.info "[TradeBrain] review_positions → #{result.output.to_s.slice(0, 80)}..."
      result
    end

    # Answer an operational question about the trading system.
    #
    # @param question [String]  free-form natural language question
    # @param context  [Hash]    optional prior conversation context (multi-turn support)
    # @return [Agents::RunResult]  result.output = answer text
    def ask(question, context: nil)
      result = AI::Runners::OperatorRunner.run(question, context: context || {})
      Rails.logger.info "[TradeBrain] ask → #{result.output.to_s.slice(0, 80)}..."
      result
    end

    # Quick single-agent market structure snapshot (cheaper than full pipeline).
    #
    # @param symbol [String]
    # @return [Agents::RunResult]
    def quick_analysis(symbol)
      agent  = AI::Agents::MarketStructureAgent.build
      runner = ::Agents::Runner.with_agents(agent)
      runner.run("Quick market structure analysis for #{symbol}. Use 15m candles.", context: {})
    end

    # Generate a complete session report: analysis + positions + proposal.
    #
    # @param symbol [String]
    # @return [Hash]  aggregated session data
    def session_report(symbol)
      analysis     = analyze(symbol)
      positions    = review_positions
      trade_result = propose(symbol: symbol)

      {
        symbol:     symbol,
        timestamp:  Time.current.iso8601,
        analysis:   analysis.output,
        positions:  positions.output,
        proposal:   trade_result[:proposal],
        validation: trade_result[:validation],
        context:    trade_result.dig(:result, :context)
      }
    end
  end
end
