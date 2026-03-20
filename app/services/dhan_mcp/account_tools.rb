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
      normalize = method(:normalized_args)
      validator = method(:validate)
      dhan_call = ->(&block) { dhan(fmt, &block) }

      @server.define_tool(
        name: 'get_fund_limits',
        description: 'Retrieve available funds, margins, and limits.',
        input_schema: { properties: {} }
      ) do |params: nil, **kwargs|
        args = normalize.call(params: params, **kwargs)
        if (err = validator.call('get_fund_limits', args))
          fmt.call({ error: err })
        else
          dhan_call.call { ::DhanHQ::Models::Funds.fetch }
        end
      end
    end

    def define_edis_inquiry(fmt)
      normalize = method(:normalized_args)
      validator = method(:validate)
      dhan_call = ->(&block) { dhan(fmt, &block) }

      @server.define_tool(
        name: 'get_edis_inquiry',
        description: 'Retrieve eDIS (electronic delivery instruction slip) inquiry status.',
        input_schema: { properties: {} }
      ) do |params: nil, **kwargs|
        args = normalize.call(params: params, **kwargs)
        if (err = validator.call('get_edis_inquiry', args))
          fmt.call({ error: err })
        else
          dhan_call.call { ::DhanHQ::Models::Edis.inquire('ALL') }
        end
      end
    end
  end
end
