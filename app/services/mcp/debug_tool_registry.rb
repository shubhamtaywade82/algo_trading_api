# frozen_string_literal: true

module Mcp
  # Debug MCP tools are exposed at POST /mcp/debug
  class DebugToolRegistry
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

