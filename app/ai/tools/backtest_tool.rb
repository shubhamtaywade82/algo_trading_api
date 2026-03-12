# frozen_string_literal: true

module AI
  module Tools
    # Runs a strategy backtest using the existing Backtest::Runner service.
    class BacktestTool < BaseTool
      TOOL_NAME   = 'run_backtest'
      DESCRIPTION = 'Run a strategy backtest for an instrument. Returns win rate, P&L, and max drawdown metrics.'
      PARAMETERS  = {
        type: 'object',
        properties: {
          symbol: {
            type: 'string',
            description: 'Instrument symbol to backtest, e.g. NIFTY, BANKNIFTY'
          },
          strategy: {
            type: 'string',
            description: 'Strategy name to backtest, e.g. supertrend, holy_grail, ema_crossover'
          },
          from_date: {
            type: 'string',
            description: 'Backtest start date YYYY-MM-DD (default: 30 days ago)'
          },
          to_date: {
            type: 'string',
            description: 'Backtest end date YYYY-MM-DD (default: today)'
          },
          interval: {
            type: 'string',
            description: 'Candle interval: 5m, 15m, 1d',
            enum: %w[5m 15m 1d]
          }
        },
        required: %w[symbol strategy]
      }.freeze

      def perform(args)
        symbol     = args['symbol'].to_s.upcase
        strategy   = args['strategy'].to_s
        interval   = args['interval'] || '15m'
        from_date  = args['from_date'] || (Time.current - 30.days).to_date.to_s
        to_date    = args['to_date']   || Time.current.to_date.to_s

        result = Backtest::Runner.run({
          symbol:    symbol,
          strategy:  strategy,
          interval:  interval,
          from_date: from_date,
          to_date:   to_date
        })

        if result.respond_to?(:winrate)
          {
            symbol:       symbol,
            strategy:     strategy,
            interval:     interval,
            from_date:    from_date,
            to_date:      to_date,
            win_rate:     result.winrate&.round(2),
            total_pnl:    result.pnl&.round(2),
            max_drawdown: result.max_drawdown&.round(2),
            trade_count:  result.try(:trade_count),
            sharpe:       result.try(:sharpe)&.round(3)
          }
        else
          {
            symbol:    symbol,
            strategy:  strategy,
            raw_result: result.to_s
          }
        end
      rescue StandardError => e
        { error: e.message }
      end
    end
  end
end
