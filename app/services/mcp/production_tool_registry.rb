# frozen_string_literal: true

module Mcp
  # Production MCP tools are exposed at POST /mcp
  class ProductionToolRegistry
    TOOL_CLASSES = [
      Tools::AnalyzeTrade,
      Tools::PlaceOrder,
      Tools::ManagePosition,
      Tools::ExitPosition,
      Tools::GetPositionsV2,
      Tools::SystemStatus,
      Tools::GetMarketSentiment,
      Tools::GetConfluenceSignal,
      Tools::GetKeyLevels,
      Tools::GetIvRank
    ].freeze

    def self.tools
      TOOL_CLASSES
    end
  end
end

