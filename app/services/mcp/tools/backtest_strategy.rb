# frozen_string_literal: true

module Mcp
  module Tools
    # Tool for backtesting an options strategy via MCP.
    class BacktestStrategy
      extend ExecutionHelpers
      def self.name
        'backtest_strategy'
      end

      def self.definition
        {
          name: name,
          title: 'Run historical backtest',
          description: 'Run a historical backtest for a strategy. Currently returns a stub; full backtest engine can be wired later.',
          inputSchema: {
            type: 'object',
            properties: {
              symbol: { type: 'string', description: 'Underlying symbol' },
              from_date: { type: 'string', description: 'Start date YYYY-MM-DD' },
              to_date: { type: 'string', description: 'End date YYYY-MM-DD' }
            },
            required: []
          }
        }
      end

      def self.execute(args)
        opts = normalize_args!(name, args)

        {
          status: 'not_implemented',
          message: 'Backtest engine is not yet wired in MCP. Use historical data tools and external backtest if needed.',
          params_received: opts.slice(:symbol, :from_date, :to_date).compact
        }
      end
    end
  end
end
