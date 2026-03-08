# frozen_string_literal: true

module Mcp
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
