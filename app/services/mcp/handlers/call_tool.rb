# frozen_string_literal: true

module Mcp
  module Handlers
    # Handler for executing a specific tool via MCP.
    class CallTool
      def self.call(req)
        params = req['params'] || {}
        name   = params['name']
        args   = params['arguments'] || {}

        tool = ToolRegistry.tools.find { |t| t.name == name }
        raise "Unknown tool: #{name}" unless tool

        result = tool.execute(args)

        {
          jsonrpc: '2.0',
          id: req['id'],
          result: {
            content: [{ type: 'text', text: result.to_json }],
            isError: false
          }
        }
      rescue StandardError => e
        {
          jsonrpc: '2.0',
          id: req['id'],
          result: {
            content: [{ type: 'text', text: { error: e.message }.to_json }],
            isError: true
          }
        }
      end
    end
  end
end
