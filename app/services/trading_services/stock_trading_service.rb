# frozen_string_literal: true

module TradingServices
  class StockTradingService < BaseTradingService
    def execute_trade
      raise "No #{@timeframe} levels found for #{@symbol_name}" unless levels

      stock_ltp = instrument.ltp
      Rails.logger.debug { "LTP: #{stock_ltp}, Demand Zone: #{levels.demand_zone}, Supply Zone: #{levels.supply_zone}" }

      case determine_trade_action(stock_ltp, levels)
      when :buy
        execute_buy_trade
      when :sell
        execute_sell_trade
      else
        Rails.logger.debug { "#{@symbol_name} is within range. No trade executed." }
      end
    end

    private

    def execute_buy_trade
      Rails.logger.debug { "#{@symbol_name} near demand zone. Placing BUY order." }
      place_order('BUY', instrument.security_id, calculate_quantity)
    end

    def execute_sell_trade
      Rails.logger.debug { "#{@symbol_name} near supply zone. Placing SELL order." }
      place_order('SELL', instrument.security_id, calculate_quantity)
    end

    def calculate_quantity
      10 # Example: Fixed quantity of 10 shares
    end
  end
end
