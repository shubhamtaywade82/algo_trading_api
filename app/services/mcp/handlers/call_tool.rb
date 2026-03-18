# frozen_string_literal: true

module Mcp
  module Handlers
    # Handler for executing a specific tool via MCP.
    class CallTool
      def self.call(req, registry: ToolRegistry)
        params = req['params'] || {}
        name   = params['name']
        args   = params['arguments'] || {}

        tool = registry.tools.find { |t| t.name == name }
        raise "Unknown tool: #{name}" unless tool

        result = tool.execute(args)
        is_error =
          result.is_a?(Hash) &&
            result.key?(:error) &&
            result[:error].present?

        {
          jsonrpc: '2.0',
          id: req['id'],
          result: {
            structuredContent: result,
            content: [{ type: 'text', text: result.to_json }],
            isError: is_error
          }
        }
      rescue StandardError => e
        {
          jsonrpc: '2.0',
          id: req['id'],
          result: {
            structuredContent: { error: e.message },
            content: [{ type: 'text', text: { error: e.message }.to_json }],
            isError: true
          }
        }
      end
    end
  end
end
