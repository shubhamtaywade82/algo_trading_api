# frozen_string_literal: true

module Backtest
  # Orchestrates long-term backtests by dividing time into chunks and aggregating results.
  class Orchestrator < ApplicationService
    def initialize(underlying:, strategy:, years: 5, initial_capital: 1_000_000.0)
      @underlying = underlying.downcase
      @strategy = strategy.to_sym
      @years = years.to_i
      @initial_capital = initial_capital.to_f
    end

    def call
      chunks = generate_monthly_chunks
      all_trades = []

      chunks.each_with_index do |chunk, index|
        Rails.logger.info "[Backtest] Batch #{index + 1}/#{chunks.size}: #{chunk[:from]} to #{chunk[:to]}"
        result = run_batch(chunk)
        all_trades.concat(result[:trades]) if result[:trades].present?
        
        # Respect rate limits if necessary
        sleep 0.5
      end

      aggregate_final_results(all_trades)
    end

    private

    def generate_monthly_chunks
      end_date = Time.zone.today - 1
      start_date = end_date - @years.years
      
      chunks = []
      curr = start_date
      while curr < end_date
        chunk_end = [curr.next_month - 1, end_date].min
        chunks << { from: curr.to_s, to: chunk_end.to_s }
        curr = curr.next_month
      end
      chunks
    end

    def run_batch(chunk)
      config = {
        underlying: @underlying,
        strategy: @strategy,
        from_date: chunk[:from],
        to_date: chunk[:to],
        capital: @initial_capital
      }
      Backtest::Engine.call(config)
    end

    def aggregate_final_results(trades)
      return { status: 'No trades' } if trades.blank?

      total_pnl = trades.sum { |t| t[:pnl].to_f }
      wins = trades.count { |t| t[:status] == 'WIN' }
      win_rate = (wins.to_f / trades.size * 100).round(2)
      
      # Simple Max Drawdown calculation
      equity_curve = [@initial_capital]
      trades.each { |t| equity_curve << (equity_curve.last + t[:pnl].to_f) }
      
      peak = @initial_capital
      max_dd = 0.0
      equity_curve.each do |val|
        peak = [peak, val].max
        dd = (peak - val) / peak
        max_dd = [max_dd, dd].max
      end

      {
        underlying: @underlying,
        strategy: @strategy,
        total_trades: trades.size,
        win_rate: "#{win_rate}%",
        net_pnl: total_pnl.round(2),
        max_drawdown: "#{(max_dd * 100).round(2)}%",
        final_equity: (@initial_capital + total_pnl).round(2),
        period: "#{@initial_capital} initial capital",
        trades_count: trades.size
      }
    end
  end
end
