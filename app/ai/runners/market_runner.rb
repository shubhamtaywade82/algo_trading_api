# frozen_string_literal: true

module AI
  module Runners
    # Market analysis pipeline using the ai-agents gem.
    #
    # Hub-and-spoke topology:
    #   SupervisorAgent (entry point)
    #     → MarketStructureAgent   (price action + trend)
    #     → OptionsFlowAgent       (IV, PCR, OI)
    #   Both specialists hand back to Supervisor for synthesis.
    #
    # Usage:
    #   result = AI::Runners::MarketRunner.run("Analyze NIFTY for today's session")
    #   puts result.output
    #   # Continue conversation:
    #   result2 = AI::Runners::MarketRunner.run("What about BANKNIFTY?", context: result.context)
    class MarketRunner
      def self.run(input, context: nil)
        supervisor = AI::Agents::SupervisorAgent.build
        market     = AI::Agents::MarketStructureAgent.build
        options    = AI::Agents::OptionsFlowAgent.build

        # Hub-and-spoke: supervisor routes to specialists; specialists hand back
        supervisor.register_handoffs(market, options)
        market.register_handoffs(supervisor)
        options.register_handoffs(supervisor)

        runner = ::Agents::Runner.with_agents(supervisor, market, options)
        runner.run(input, context: context || {})
      end
    end
  end
end
