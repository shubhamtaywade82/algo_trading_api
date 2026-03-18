# frozen_string_literal: true

module Mcp
  module Handlers
    # Handler for listing available MCP tools.
    class ListTools
      def self.call(req, registry: ToolRegistry)
        tools = registry.tools.map(&:definition)

        {
          jsonrpc: '2.0',
          id: req['id'],
          result: { tools: tools }
        }
      end
    end
  end
end
