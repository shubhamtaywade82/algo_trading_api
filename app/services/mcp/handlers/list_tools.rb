# frozen_string_literal: true

module Mcp
  module Handlers
    class ListTools
      def self.call(req)
        tools = ToolRegistry.tools.map(&:definition)

        {
          jsonrpc: '2.0',
          id: req['id'],
          result: { tools: tools }
        }
      end
    end
  end
end
