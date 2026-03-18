# frozen_string_literal: true

module Mcp
  # Registry for all available MCP tools in the system.
  class ToolRegistry
    def self.tools
      ProductionToolRegistry.tools
    end
  end
end
