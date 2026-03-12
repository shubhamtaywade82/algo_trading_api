# frozen_string_literal: true

module AI
  module Runners
    # Runs the market analysis pipeline: structure → options flow → synthesis.
    #
    # Usage:
    #   result = AI::Runners::MarketRunner.run("Analyze NIFTY for today's session")
    #   result[:final][:parsed]
    #   # => { "symbol" => "NIFTY", "bias" => "bullish", ... }
    class MarketRunner < BaseRunner
      PIPELINE = [
        AI::Agents::MarketStructureAgent,
        AI::Agents::OptionsFlowAgent
      ].freeze

      SYNTHESIZER = AI::Agents::SupervisorAgent
    end
  end
end
