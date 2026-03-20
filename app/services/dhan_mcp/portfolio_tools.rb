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
      normalize = method(:normalized_args)
      validator = method(:validate)
      dhan_call = ->(&block) { dhan(fmt, &block) }

      @server.define_tool(
        name: 'get_holdings',
        description: 'Retrieve current portfolio holdings.',
        input_schema: { properties: {} }
      ) do |params: nil, **kwargs|
        args = normalize.call(params: params, **kwargs)
        if (err = validator.call('get_holdings', args))
          fmt.call({ error: err })
        else
          dhan_call.call { ::DhanHQ::Models::Holding.all }
        end
      end
    end

    def define_positions(fmt)
      normalize = method(:normalized_args)
      validator = method(:validate)
      dhan_call = ->(&block) { dhan(fmt, &block) }

      @server.define_tool(
        name: 'get_positions',
        description: 'Retrieve current open positions (intraday and delivery).',
        input_schema: { properties: {} }
      ) do |params: nil, **kwargs|
        args = normalize.call(params: params, **kwargs)
        if (err = validator.call('get_positions', args))
          fmt.call({ error: err })
        else
          dhan_call.call { ::DhanHQ::Models::Position.all }
        end
      end
    end
  end
end
