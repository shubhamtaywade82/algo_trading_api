# frozen_string_literal: true

module DhanMcp
  # Account-related tools for DhanHQ MCP.
  class AccountTools < BaseTool
    def define(fmt)
      define_fund_limits(fmt)
      define_edis_inquiry(fmt)
    end

    private

    def define_fund_limits(fmt)
      @server.define_tool(
        name: 'get_fund_limits',
        description: 'Retrieve available funds, margins, and limits.',
        input_schema: { properties: {} }
      ) { |**_| dhan(fmt) { ::DhanHQ::Models::Funds.fetch } }
    end

    def define_edis_inquiry(fmt)
      @server.define_tool(
        name: 'get_edis_inquiry',
        description: 'Retrieve eDIS (electronic delivery instruction slip) inquiry status.',
        input_schema: { properties: {} }
      ) { |**_| dhan(fmt) { ::DhanHQ::Models::Edis.inquire('ALL') } }
    end
  end
end
