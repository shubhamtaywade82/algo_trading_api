# frozen_string_literal: true

module Mcp
  module Tools
    # Tool for explaining a trade setup via MCP using LLM.
    class ExplainTrade
      def self.name
        'explain_trade'
      end

      def self.definition
        {
          name: name,
          title: 'AI explanation of a trade',
          description: 'Get an AI-generated explanation of a trade or position (e.g. rationale, risk).',
          inputSchema: {
            type: 'object',
            properties: {
              query: { type: 'string', description: 'Short description of the trade or question' },
              context: { type: 'string', description: 'Optional context (symbol, side, etc.)' }
            },
            required: ['query']
          }
        }
      end

      def self.execute(args)
        query = args['query'] || args[:query]
        raise ArgumentError, 'query is required' if query.blank?

        context = args['context'] || args[:context]
        prompt = context.present? ? "#{query}\n\nContext: #{context}" : query

        answer = Openai::MessageProcessor.call(prompt, model: nil, system: nil)
        text = answer.is_a?(Hash) ? (answer[:text] || answer['text'] || answer) : answer.to_s
        { explanation: text }
      rescue StandardError => e
        { error: e.message }
      end
    end
  end
end
