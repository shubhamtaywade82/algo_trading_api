# frozen_string_literal: true

module AI
  module Runners
    # Abstract base for all agent runners.
    #
    # A Runner orchestrates multiple agents in sequence and aggregates their
    # outputs into a final result. Each agent's output is passed as context
    # to the next agent in the pipeline.
    #
    # Sub-classes define PIPELINE as an ordered array of agent classes
    # plus an optional SYNTHESIZER agent.
    class BaseRunner
      # @param input [String]  the user's task or query
      # @param opts  [Hash]    optional overrides (model, context, etc.)
      def self.run(input, **opts)
        new(input, **opts).run
      end

      def initialize(input, model: nil, extra_context: {})
        @input         = input
        @model         = model
        @extra_context = extra_context
      end

      def run
        accumulated_context = @extra_context.dup
        pipeline_results    = []

        pipeline_agents.each do |agent_class|
          context_input = build_agent_input(agent_class, accumulated_context)

          result = agent_class.run(
            context_input,
            model:   @model,
            context: accumulated_context
          )

          pipeline_results << result
          accumulated_context = merge_result_into_context(accumulated_context, agent_class, result)

          Rails.logger.info "[#{runner_name}] #{agent_class.name} → #{result[:iterations]} iterations, error=#{result[:error]}"
        end

        final = synthesize(accumulated_context, pipeline_results)

        {
          input:            @input,
          runner:           runner_name,
          pipeline_results: pipeline_results,
          final:            final,
          success:          !pipeline_results.any? { |r| r[:error] }
        }
      rescue StandardError => e
        Rails.logger.error "[#{runner_name}] ❌ #{e.class}: #{e.message}"
        { input: @input, runner: runner_name, error: e.message, success: false }
      end

      private

      # Sub-classes return the ordered list of agent classes to run.
      def pipeline_agents
        self.class::PIPELINE rescue []
      end

      # Sub-classes return the synthesizer agent class (optional).
      def synthesizer_agent
        self.class::SYNTHESIZER rescue nil
      end

      # Build the prompt for a specific agent, injecting previous results.
      def build_agent_input(agent_class, context)
        base = @input
        return base if context.blank?

        ctx_lines = context.map { |k, v| "#{k}:\n#{v.is_a?(Hash) ? v.to_json : v}" }
        "#{base}\n\n--- Context from previous analysis ---\n#{ctx_lines.join("\n\n")}"
      end

      # After each agent runs, merge its parsed output into context for next agent.
      def merge_result_into_context(context, agent_class, result)
        key = agent_class.name.demodulize.underscore
        context.merge(key => result[:parsed] || result[:output])
      end

      # Final synthesis step: run the synthesizer agent or return the last result.
      def synthesize(context, pipeline_results)
        return pipeline_results.last unless synthesizer_agent

        synthesis_input = build_synthesis_prompt(pipeline_results)

        synthesizer_agent.run(
          synthesis_input,
          model:   @model,
          context: context
        )
      end

      def build_synthesis_prompt(pipeline_results)
        parts = pipeline_results.map.with_index do |r, i|
          agent_label = r[:agent] || "Agent #{i + 1}"
          "#{agent_label}:\n#{r[:output]}"
        end

        "Synthesize the following specialist agent outputs:\n\n#{parts.join("\n\n---\n\n")}"
      end

      def runner_name
        self.class.name || 'AI::Runner'
      end
    end
  end
end
