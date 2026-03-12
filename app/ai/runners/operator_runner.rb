# frozen_string_literal: true

module AI
  module Runners
    # Single-agent runner for operational/debug queries.
    #
    # Usage:
    #   result = AI::Runners::OperatorRunner.run("Why did NIFTY CE 24300 exit early today?")
    #   puts result[:final][:output]
    class OperatorRunner < BaseRunner
      PIPELINE    = [AI::Agents::OperatorAgent].freeze
      SYNTHESIZER = nil

      def run
        result = super

        # OperatorRunner always returns a text answer (not JSON)
        final_output = result.dig(:pipeline_results, 0, :output)

        result.merge(
          final:   { output: final_output, parsed: nil, agent: 'OperatorAgent' },
          answer:  final_output
        )
      end
    end
  end
end
