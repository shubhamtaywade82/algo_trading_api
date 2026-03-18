# frozen_string_literal: true

module Mcp
  class ProductionToolRegistry
    TOOL_CLASSES = [].freeze  # will be populated in later phases

    def self.tools
      TOOL_CLASSES
    end
  end
end
