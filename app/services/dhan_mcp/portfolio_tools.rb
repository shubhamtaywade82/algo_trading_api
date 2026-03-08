# frozen_string_literal: true

module DhanMcp
  # Portfolio-related tools for DhanHQ MCP.
  class PortfolioTools < BaseTool
    def define(fmt)
      define_holdings(fmt)
      define_positions(fmt)
    end

    private

    def define_holdings(fmt)
      @server.define_tool(
        name: 'get_holdings',
        description: 'Retrieve current portfolio holdings.',
        input_schema: { properties: {} }
      ) { |**_| dhan(fmt) { ::DhanHQ::Models::Holding.all } }
    end

    def define_positions(fmt)
      @server.define_tool(
        name: 'get_positions',
        description: 'Retrieve current open positions (intraday and delivery).',
        input_schema: { properties: {} }
      ) { |**_| dhan(fmt) { ::DhanHQ::Models::Position.all } }
    end
  end
end
