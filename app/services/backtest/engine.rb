# frozen_string_literal: true

module Backtest
  # Simple backtest engine that iterates through historical data and applies a strategy.
  class Engine < ApplicationService
    def initialize(config)
      @symbol = config[:underlying].to_s.upcase
      @strategy_name = config[:strategy]
      @from_date = config[:from_date]
      @to_date = config[:to_date]
      @interval = config[:interval] || '5'
      @initial_capital = config[:capital] || 1_000_000.0
    end

    def call
      instrument = Instrument.find_by(underlying_symbol: @symbol) || Instrument.find_by(symbol_name: @symbol)
      return { error: 'Instrument not found' } unless instrument

      # Fetch historical data for the underlying
      bars = instrument.intraday_ohlc(
        from_date: @from_date,
        to_date: @to_date,
        interval: @interval
      )

      return { trades: [], status: 'No data' } if bars.blank? || bars['close'].blank?

      # Run the strategy simulation
      trades = simulate_strategy(instrument, bars)

      {
        trades: trades,
        period: "#{@from_date} to #{@to_date}",
        total_pnl: trades.sum { |t| t[:pnl].to_f }.round(2)
      }
    end

    private

    def simulate_strategy(instrument, bars)
      # This is a very simplified simulation. 
      # In a real backtest, we'd iterate bar by bar and maintain state.
      trades = []
      
      # For demonstration, let's say we find "signals" using HolyGrail
      # We need at least 100 bars for HolyGrail
      close_prices = bars['close']
      return [] if close_prices.size < 105

      # Sliding window backtest
      (100...close_prices.size).step(1).each do |i|
        window = slice_bars(bars, i - 100, 100)
        
        begin
          analysis = Indicators::HolyGrail.call(candles: window)
          if analysis.proceed?
            # Simulate a trade
            trades << execute_simulated_trade(instrument, bars, i, analysis.bias)
          end
        rescue StandardError => e
          # Skip errors during simulation
          next
        end
      end

      trades
    end

    def slice_bars(bars, start, length)
      {
        'open' => bars['open'][start, length],
        'high' => bars['high'][start, length],
        'low' => bars['low'][start, length],
        'close' => bars['close'][start, length],
        'timestamp' => bars['timestamp'][start, length],
        'volume' => bars['volume'][start, length]
      }
    end

    def execute_simulated_trade(instrument, bars, index, bias)
      entry_price = bars['close'][index].to_f
      # Very simple: exit after 5 bars or at end of day
      exit_index = [index + 5, bars['close'].size - 1].min
      exit_price = bars['close'][exit_index].to_f
      
      pnl = bias == :bullish ? (exit_price - entry_price) : (entry_price - exit_price)
      # Scale by some quantity
      quantity = 50 
      
      {
        entry_time: Time.zone.at(bars['timestamp'][index]),
        exit_time: Time.zone.at(bars['timestamp'][exit_index]),
        side: bias == :bullish ? 'BUY' : 'SELL',
        entry_price: entry_price,
        exit_price: exit_price,
        pnl: (pnl * quantity).round(2),
        status: pnl > 0 ? 'WIN' : 'LOSS'
      }
    end
  end
end
