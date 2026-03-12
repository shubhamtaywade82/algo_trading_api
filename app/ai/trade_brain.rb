# frozen_string_literal: true

module AI
  # TradeBrain — public façade for the AI agent cluster.
  #
  # This is the single entry point into the AI orchestration layer.
  # It provides clean, high-level methods that can be called from:
  #   - Rails console
  #   - Background jobs
  #   - Controllers (AiAgentsController)
  #   - The Ai service facade (app/services/ai.rb)
  #
  # Critical boundary: TradeBrain produces PROPOSALS. It never executes orders.
  # Execution always goes through the deterministic Strategy::Validator → Orders::Executor pipeline.
  #
  # Usage:
  #   # Market analysis
  #   AI::TradeBrain.analyze("NIFTY")
  #
  #   # Full trade proposal
  #   proposal = AI::TradeBrain.propose(symbol: "NIFTY")
  #   Orders::Executor.place(proposal) if Strategy::Validator.valid?(proposal)
  #
  #   # Operator query
  #   AI::TradeBrain.ask("Why did trade #214 exit early?")
  module TradeBrain
    module_function

    # Run the full market analysis pipeline for a symbol.
    #
    # @param symbol  [String]  NSE index symbol, e.g. "NIFTY"
    # @param candle  [String]  timeframe, e.g. "15m"
    # @return [Hash]  { bias:, trend:, key_levels:, confidence:, ... }
    def analyze(symbol, candle: '15m')
      input = "Analyze #{symbol} market structure and options flow for the current session. " \
              "Use #{candle} candle data."

      result = AI::Runners::MarketRunner.run(input)
      Rails.logger.info "[TradeBrain] analyze(#{symbol}) → success=#{result[:success]}"

      result
    end

    # Generate a trade proposal for a symbol, validated through the risk agent.
    #
    # The returned proposal must pass Strategy::Validator.valid? before execution.
    #
    # @param symbol    [String]  NSE index symbol
    # @param direction [String]  optional hint: "CE", "PE", or nil (auto)
    # @return [Hash]   trade proposal with :risk_approved key
    def propose(symbol:, direction: nil)
      dir_hint = direction ? " Preferred direction: #{direction}." : ''
      input    = "Generate a concrete options trade setup for #{symbol}.#{dir_hint} " \
                 "Include specific strike, entry, stop-loss, and target."

      result = AI::Runners::TradeRunner.run(input)
      Rails.logger.info "[TradeBrain] propose(#{symbol}) → proposal=#{result[:proposal].inspect}"

      result
    end

    # Analyze all current positions for risk and exit recommendations.
    #
    # @return [Hash]  runner result with position insights
    def review_positions
      result = AI::Runners::OperatorRunner.run(
        "Review all current open positions. Assess P&L, risk level, " \
        "and flag any positions that should be considered for exit."
      )

      Rails.logger.info "[TradeBrain] review_positions → #{result[:answer]&.slice(0, 80)}..."
      result
    end

    # Answer an operational question about the trading system.
    #
    # @param question [String]  free-form question
    # @return [Hash]   { answer: String, ... }
    def ask(question)
      result = AI::Runners::OperatorRunner.run(question)
      Rails.logger.info "[TradeBrain] ask → #{result[:answer]&.slice(0, 80)}..."
      result
    end

    # Run a quick single-agent market structure snapshot.
    # Cheaper than the full pipeline — useful for frequent polling.
    #
    # @param symbol [String]
    # @return [Hash]  agent result with parsed JSON
    def quick_analysis(symbol)
      AI::Agents::MarketStructureAgent.run(
        "Quick market structure analysis for #{symbol}. Use 15m candles."
      )
    end

    # Generate a complete session report: analysis + positions + proposal.
    #
    # @param symbol [String]
    # @return [Hash]  aggregated session report
    def session_report(symbol)
      analysis  = analyze(symbol)
      positions = review_positions
      proposal  = propose(symbol: symbol)

      {
        symbol:    symbol,
        timestamp: Time.current.iso8601,
        analysis:  analysis,
        positions: positions,
        proposal:  proposal[:proposal],
        success:   analysis[:success] && proposal[:success]
      }
    end
  end
end
