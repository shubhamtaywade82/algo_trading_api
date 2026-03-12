# frozen_string_literal: true

module AI
  module Runners
    # Full trade planning pipeline using the ai-agents gem.
    #
    # Topology (supervisor orchestrates, specialists do work):
    #   SupervisorAgent (entry point)
    #     → MarketStructureAgent  (market structure)
    #     → OptionsFlowAgent      (options flow)
    #     → TradePlannerAgent     (trade setup)
    #     → RiskAgent             (risk validation)
    #   All specialists hand back to supervisor for final synthesis.
    #
    # Usage:
    #   result = AI::Runners::TradeRunner.run("Generate a NIFTY trade setup for today")
    #   puts result.output
    #
    #   # Parse the proposal from the output
    #   proposal = AI::Runners::TradeRunner.extract_proposal(result.output)
    #   Orders::Executor.place(proposal) if Strategy::Validator.valid?(proposal)
    class TradeRunner
      def self.run(input, context: nil)
        supervisor = AI::Agents::SupervisorAgent.build
        market     = AI::Agents::MarketStructureAgent.build
        options    = AI::Agents::OptionsFlowAgent.build
        planner    = AI::Agents::TradePlannerAgent.build
        risk       = AI::Agents::RiskAgent.build

        # Supervisor routes to all specialists
        supervisor.register_handoffs(market, options, planner, risk)

        # Specialists hand back to supervisor (or can cross-hand to risk)
        market.register_handoffs(supervisor)
        options.register_handoffs(supervisor)
        planner.register_handoffs(supervisor, risk)
        risk.register_handoffs(supervisor)

        runner = ::Agents::Runner.with_agents(supervisor, market, options, planner, risk)
        runner.run(input, context: context || {})
      end

      # Extract a structured trade proposal from the agent's text output.
      # Looks for a JSON block (optionally after "PROPOSAL:") in the output.
      #
      # @param output [String]  text from result.output
      # @return [Hash, nil]
      def self.extract_proposal(output)
        return nil if output.blank?

        # Try to find a JSON block after "PROPOSAL:" marker
        json_str = output[/PROPOSAL:\s*```(?:json)?\s*(.*?)```/im, 1] ||
                   output[/PROPOSAL:\s*(\{.*?\})/im, 1] ||
                   output[/```(?:json)?\s*(\{.*?\})\s*```/im, 1] ||
                   output[/(\{[^{}]*"direction"[^{}]*\})/im, 1]

        return nil unless json_str

        JSON.parse(json_str.strip)
      rescue JSON::ParserError
        nil
      end
    end
  end
end
