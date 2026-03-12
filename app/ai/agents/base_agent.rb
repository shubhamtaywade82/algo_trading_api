# frozen_string_literal: true

module AI
  module Agents
    # Base class for all AI agents.
    #
    # Wraps the OpenAI function-calling loop so each agent can focus on its
    # domain-specific system prompt and toolset rather than the plumbing.
    #
    # Usage:
    #   class MarketStructureAgent < AI::Agents::BaseAgent
    #     INSTRUCTIONS = "Analyze NSE/BSE market structure..."
    #     TOOLS = [AI::Tools::DhanCandleTool, AI::Tools::MarketSentimentTool]
    #   end
    #
    #   result = MarketStructureAgent.run("Analyze NIFTY for today")
    #   # => { output: "...", parsed: {...}, tool_calls: [...], iterations: 3 }
    class BaseAgent
      MAX_ITERATIONS  = 8    # guard against infinite tool-call loops
      DEFAULT_MODEL   = 'gpt-4o'

      # Sub-classes declare these:
      # INSTRUCTIONS = "..."
      # TOOLS        = [AI::Tools::SomeTool, ...]

      # @param input  [String]  user message / task description
      # @param model  [String]  override LLM model
      # @param context [Hash]   optional key/value context injected into system prompt
      def self.run(input, model: nil, context: {})
        new(input, model: model, context: context).run
      end

      def initialize(input, model: nil, context: {})
        @input   = input.to_s
        @model   = model || resolve_model
        @context = context
      end

      # Main agent loop: call LLM → execute tools → repeat until done.
      #
      # @return [Hash] { output:, parsed:, tool_calls:, iterations:, agent: }
      def run
        messages    = build_initial_messages
        tool_calls  = []
        iterations  = 0

        loop do
          iterations += 1
          raise "#{agent_name} exceeded max iterations (#{MAX_ITERATIONS})" if iterations > MAX_ITERATIONS

          response = call_llm(messages)
          choice   = response.dig('choices', 0)
          message  = choice&.dig('message') || {}

          # Accumulate assistant turn
          messages << message

          # If the LLM requests tool calls, execute them and continue
          if message['tool_calls'].present?
            results = execute_tool_calls(message['tool_calls'])
            tool_calls.concat(results)
            messages.concat(tool_result_messages(results))
          else
            # Final answer
            output = message['content'].to_s.strip
            return build_result(output, tool_calls, iterations)
          end
        end
      rescue StandardError => e
        Rails.logger.error "[#{agent_name}] ❌ #{e.class}: #{e.message}"
        { output: "Agent error: #{e.message}", parsed: nil, tool_calls: tool_calls, iterations: iterations, agent: agent_name, error: true }
      end

      private

      # -----------------------------------------------------------------------
      # Prompt construction
      # -----------------------------------------------------------------------

      def build_initial_messages
        [
          { role: 'system', content: system_prompt },
          { role: 'user',   content: @input }
        ]
      end

      def system_prompt
        base = self.class::INSTRUCTIONS rescue "You are a helpful trading assistant."
        return base if @context.blank?

        ctx_block = @context.map { |k, v| "#{k}: #{v}" }.join("\n")
        "#{base}\n\nContext:\n#{ctx_block}"
      end

      # -----------------------------------------------------------------------
      # LLM call
      # -----------------------------------------------------------------------

      def call_llm(messages)
        params = {
          model: @model,
          messages: messages
        }

        tool_definitions = build_tool_definitions
        params[:tools] = tool_definitions if tool_definitions.present?
        params[:tool_choice] = 'auto'     if tool_definitions.present?

        openai_client.chat(parameters: params)
      end

      def openai_client
        @openai_client ||= ::Openai::Client.instance
      end

      # -----------------------------------------------------------------------
      # Tool management
      # -----------------------------------------------------------------------

      def tools
        @tools ||= (self.class::TOOLS rescue []).map(&:new)
      end

      def build_tool_definitions
        tools.map(&:to_openai_definition)
      end

      def execute_tool_calls(llm_tool_calls)
        llm_tool_calls.map do |tc|
          tool_name = tc.dig('function', 'name')
          raw_args  = tc.dig('function', 'arguments').to_s

          args = begin
            JSON.parse(raw_args)
          rescue JSON::ParserError
            {}
          end

          tool = tools.find { |t| t.name == tool_name }

          result = if tool
                     begin
                       tool.perform(args)
                     rescue StandardError => e
                       Rails.logger.warn "[#{agent_name}] Tool #{tool_name} failed: #{e.message}"
                       { error: e.message }
                     end
                   else
                     { error: "Unknown tool: #{tool_name}" }
                   end

          {
            id:        tc['id'],
            tool_name: tool_name,
            args:      args,
            result:    result
          }
        end
      end

      def tool_result_messages(results)
        results.map do |r|
          {
            role:         'tool',
            tool_call_id: r[:id],
            content:      r[:result].to_json
          }
        end
      end

      # -----------------------------------------------------------------------
      # Output
      # -----------------------------------------------------------------------

      def build_result(output, tool_calls, iterations)
        parsed = try_parse_json(output)
        {
          output:     output,
          parsed:     parsed,
          tool_calls: tool_calls,
          iterations: iterations,
          agent:      agent_name
        }
      end

      def try_parse_json(str)
        # Strip markdown code fences if present
        clean = str.gsub(/\A```(?:json)?\s*/m, '').gsub(/\s*```\z/m, '').strip
        JSON.parse(clean)
      rescue JSON::ParserError
        nil
      end

      def agent_name
        self.class.name || 'AI::Agent'
      end

      def resolve_model
        using_ollama? ? ollama_model : DEFAULT_MODEL
      end

      def using_ollama?
        return false if Rails.env.production?

        base = ENV['OPENAI_URI_BASE'].to_s
        base.blank? || base.include?('11434')
      end

      def ollama_model
        ENV['OPENAI_OLLAMA_MODEL'].presence || ENV['OLLAMA_MODEL'].presence || 'qwen3:latest'
      end
    end
  end
end
