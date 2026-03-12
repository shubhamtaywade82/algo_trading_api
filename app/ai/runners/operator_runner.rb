# frozen_string_literal: true

module AI
  module Runners
    # Single-agent runner for operational/debug queries.
    #
    # Uses only the OperatorAgent — no handoffs needed for simple queries.
    #
    # Usage:
    #   result = AI::Runners::OperatorRunner.run("Why did NIFTY CE 24300 exit early today?")
    #   puts result.output
    class OperatorRunner
      def self.run(input, context: nil)
        agent  = AI::Agents::OperatorAgent.build
        runner = ::Agents::Runner.with_agents(agent)
        runner.run(input, context: context || {})
      end
    end
  end
end
