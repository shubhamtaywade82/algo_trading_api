# frozen_string_literal: true

module Market
  # Analyzes Intraday Buying Behaviour using synchronized Spot and Option data.
  class IntradayBehaviourService < ApplicationService
    def initialize(symbol: 'NIFTY', date: Time.zone.today, interval: '5')
      @symbol = symbol.upcase
      @date = date
      @interval = interval
    end

    def call
      instrument = find_instrument
      return { error: "Instrument not found for #{@symbol}" } unless instrument
      
      lot_size = resolve_lot_size(instrument)

      # 1. Get Synchronized Data
      tape = Market::IntradaySynchronizer.call(
        symbol: @symbol,
        date: @date,
        interval: @interval,
        strikes: ['ATM', 'ATM+1', 'ATM-1']
      )

      return tape if tape.is_a?(Hash) && tape[:error]

      # 2. Simulate Trades based on Spot Signal
      trades = []
      
      Rails.logger.info "[IntradayBehaviour] Analyzing #{tape.size} bars for #{@symbol} on #{@date} (Lot Size: #{lot_size})"
      
      tape.each_with_index do |snapshot, i|
        next if i < 2 
        
        # Signal: Spot close > max of last 2 highs
        spot_c = snapshot[:spot][:c]
        prev_highs = tape[i-2...i].map { |s| s[:spot][:h] }
        
        if spot_c > prev_highs.max
          # POTENTIAL LONG ENTRY
          entry_premium = snapshot[:ce_atm]&.[](:c)
          next unless entry_premium
          
          # Target: Exit after 2 bars
          exit_idx = [i + 2, tape.size - 1].min
          exit_snapshot = tape[exit_idx]
          exit_premium = exit_snapshot[:ce_atm]&.[](:c)
          
          if exit_premium
            pnl_points = (exit_premium - entry_premium)
            trades << {
              time: snapshot[:time],
              spot_at_entry: spot_c,
              option: 'ATM CE',
              entry: entry_premium,
              exit: exit_premium,
              pnl_pct: ((pnl_points / entry_premium) * 100).round(2),
              pnl_absolute: (pnl_points * lot_size).round(2),
              hold_time_mins: (exit_idx - i) * @interval.to_i
            }
          end
        end
      end

      {
        symbol: @symbol,
        date: @date,
        lot_size: lot_size,
        trades_found: trades.size,
        avg_pnl_pct: trades.any? ? (trades.sum { |t| t[:pnl_pct] } / trades.size).round(2) : 0,
        total_pnl_absolute: trades.sum { |t| t[:pnl_absolute] }.round(2),
        trades: trades
      }
    end

    private

    def find_instrument
      Instrument.find_by(underlying_symbol: @symbol) || Instrument.find_by(symbol_name: @symbol)
    end

    def resolve_lot_size(instrument)
      return instrument.lot_size if instrument.lot_size.to_i > 1
      d_lot = instrument.derivatives.first&.lot_size
      return d_lot if d_lot.to_i > 1

      case @symbol
      when 'NIFTY' then 25
      when 'BANKNIFTY' then 15
      when 'SENSEX' then 10
      else 1
      end
    end
  end
end
