# frozen_string_literal: true

module Orders
  class RiskManager < ApplicationService
    STOP_LOSS_PCT    = { stock: 10.0,  option: 30.0  }.freeze  # %
    TAKE_PROFIT_PCT  = { stock: 25.0,  option: 60.0  }.freeze  # %
    TRAIL_BUFFER_PCT = { stock: 5.0,   option: 15.0  }.freeze  # %
    MAX_RUPEE_LOSS   = 500.0 # absolute max rupee loss per position

    def initialize(position, analysis)
      @pos     = position
      @a       = analysis
      @key     = cache_key(@pos)
      @cache   = load_cache
      @max_pct = @cache[@key] || @a[:pnl_pct]
    end

    def call
      charges = Charges::Calculator.call(@pos, @a)
      net_pnl = @a[:pnl] - charges

      store_max_pct if @a[:pnl_pct] > @max_pct

      # 1) Take profit (net)
      if net_pnl >= (@a[:entry_price] * TAKE_PROFIT_PCT[@a[:instrument_type]] / 100.0)
        TelegramNotifier.send_message("✅ TP Hit: #{@pos['tradingSymbol']} | Net ₹#{net_pnl.round(2)}")
        return { exit: true, exit_reason: "TakeProfit_Net_#{net_pnl}" }
      end

      # 2) Absolute rupee stop loss
      if net_pnl <= -MAX_RUPEE_LOSS
        TelegramNotifier.send_message("🛑 Rupee SL Hit: #{@pos['tradingSymbol']} | Net ₹#{net_pnl.round(2)}")
        return { exit: true, exit_reason: "RupeeStopLoss_#{net_pnl}" }
      end

      # 3) Percentage stop loss
      if @a[:pnl_pct] <= -STOP_LOSS_PCT[@a[:instrument_type]]
        TelegramNotifier.send_message("🛑 % SL Hit: #{@pos['tradingSymbol']} | P&L #{@a[:pnl_pct]}%")
        return { exit: true, exit_reason: "StopLoss_#{@a[:pnl_pct]}%" }
      end

      # 4) Break-even trail
      if @a[:pnl_pct] >= 40 && @a[:ltp] <= @a[:entry_price]
        TelegramNotifier.send_message("📉 BE Trail Exit: #{@pos['tradingSymbol']} | Price fallback to entry.")
        return { exit: true, exit_reason: "BreakEven_Trail_#{@a[:pnl_pct]}%" }
      end

      # 5) Trailing stop adjustment
      drawdown = @max_pct - @a[:pnl_pct]
      if (@a[:pnl_pct]).positive? && drawdown >= TRAIL_BUFFER_PCT[@a[:instrument_type]]
        new_trigger = (@a[:ltp] * (1 - (TRAIL_BUFFER_PCT[@a[:instrument_type]] / 100))).round(2)
        return {
          adjust: true,
          adjust_params: { trigger_price: new_trigger }
        }
      end

      { exit: false, adjust: false }
    end

    private

    def cache_key(pos)
      "#{pos['securityId']}_#{pos['exchangeSegment']}"
    end

    def load_cache
      Rails.cache.read(@key) || @a[:pnl_pct]
    end

    def store_max_pct
      Rails.cache.write(@key, @a[:pnl_pct], expires_in: 1.day)
    end
  end
end
