# frozen_string_literal: true

module AI
  module Tools
    # Runs a strategy backtest using the existing Backtest::Runner service.
    class BacktestTool < Agents::Tool
      description 'Run a strategy backtest for an instrument. Returns win rate, P&L, and max drawdown metrics.'

      param :symbol,    type: 'string', desc: 'Instrument symbol to backtest, e.g. NIFTY, BANKNIFTY'
      param :strategy,  type: 'string', desc: 'Strategy name: supertrend, holy_grail, ema_crossover'
      param :from_date, type: 'string', desc: 'Backtest start date YYYY-MM-DD (default: 30 days ago)', required: false
      param :to_date,   type: 'string', desc: 'Backtest end date YYYY-MM-DD (default: today)', required: false
      param :interval,  type: 'string', desc: 'Candle interval: 5m, 15m, 1d', required: false

      def perform(_ctx, symbol:, strategy:, from_date: nil, to_date: nil, interval: '15m')
        sym       = symbol.to_s.upcase
        from_date ||= (Time.current - 30.days).to_date.to_s
        to_date   ||= Time.current.to_date.to_s

        result = Backtest::Runner.run(
          symbol:    sym,
          strategy:  strategy,
          interval:  interval,
          from_date: from_date,
          to_date:   to_date
        )

        if result.respond_to?(:winrate)
          {
            symbol:       sym,
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
          { symbol: sym, strategy: strategy, raw_result: result.to_s }
        end
      rescue StandardError => e
        { error: e.message }
      end
    end
  end
end
