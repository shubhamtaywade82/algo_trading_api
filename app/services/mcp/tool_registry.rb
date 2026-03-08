# frozen_string_literal: true

module Mcp
  # Registry for all available MCP tools in the system.
  class ToolRegistry
    TOOL_CLASSES = [
      Tools::GetOptionChain,
      Tools::ScanTradeSetup,
      Tools::PlaceTrade,
      Tools::CloseTrade,
      Tools::GetPositions,
      Tools::GetMarketData,
      Tools::BacktestStrategy,
      Tools::ExplainTrade
    ].freeze

    def self.tools
      TOOL_CLASSES
    end
  end
end
