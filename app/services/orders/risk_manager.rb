# frozen_string_literal: true

module Orders
  class RiskManager < ApplicationService
    STOP_LOSS_PCT    = { stock: 10.0,  option: 20.0  }.freeze  # %
    TAKE_PROFIT_PCT  = { stock: 25.0,  option: 40.0  }.freeze  # %
    TRAIL_BUFFER_PCT = { stock: 5.0,   option: 15.0  }.freeze  # %
    MAX_RUPEE_LOSS   = 500.0 # traditional rupee stop
    DANGER_ZONE_LOSS = -1000.0 # how deep to allow
    DANGER_ZONE_MIN  = -500.0
    DANGER_ZONE_BARS = 3       # max bars to allow in this zone

    def initialize(position, analysis)
      @pos      = position
      @a        = analysis
      @key      = cache_key(@pos)
      @cache    = load_cache
      @max_pct  = @cache[:max_pct] || @a[:pnl_pct]
      @danger_count = @cache[:danger_zone_count] || 0
    end

    def call
      charges = Charges::Calculator.call(@pos, @a)
      net_pnl = @a[:pnl] - charges

      # Keep track of max profit
      store_max_pct if @a[:pnl_pct] > @max_pct

      # === 1. Take profit (net)
      if net_pnl >= (@a[:entry_price] * @a[:quantity] * TAKE_PROFIT_PCT[@a[:instrument_type]] / 100.0)
        TelegramNotifier.send_message("✅ TP Hit: #{@pos['tradingSymbol']} | Net ₹#{net_pnl.round(2)}")
        return { exit: true, exit_reason: "TakeProfit_Net_#{net_pnl}" }
      end

      # === 2. Danger zone buffer logic ===
      # If PNL is between -1000 and -500, increment the counter. Else reset.
      if net_pnl <= DANGER_ZONE_MIN && net_pnl > DANGER_ZONE_LOSS
        @danger_count += 1
        store_danger_count(@danger_count)
      else
        reset_danger_count
      end

      # Hard exit if we've been in danger zone for too many bars
      if @danger_count >= DANGER_ZONE_BARS || net_pnl <= DANGER_ZONE_LOSS
        reset_danger_count
        TelegramNotifier.send_message("⚠️ Danger Zone Exit: #{@pos['tradingSymbol']} | Net ₹#{net_pnl.round(2)}")
        return { exit: true, exit_reason: "DangerZone_#{net_pnl}", order_type: :limit }
      end

      # === 3. Hard SL if loss is way below DANGER_ZONE_LOSS (emergency)
      if net_pnl <= -3000
        reset_danger_count
        TelegramNotifier.send_message("🛑 Emergency SL: #{@pos['tradingSymbol']} | Net ₹#{net_pnl.round(2)}")
        return { exit: true, exit_reason: "EmergencyStopLoss_#{net_pnl}" }
      end

      # === 4. Percentage stop loss
      if @a[:pnl_pct] <= -STOP_LOSS_PCT[@a[:instrument_type]]
        TelegramNotifier.send_message("🛑 % SL Hit: #{@pos['tradingSymbol']} | P&L #{@a[:pnl_pct]}%")
        return { exit: true, exit_reason: "StopLoss_#{@a[:pnl_pct]}%" }
      end

      # === 5. Break-even trail
      if @a[:pnl_pct] >= 40 && @a[:ltp] <= @a[:entry_price]
        TelegramNotifier.send_message("📉 BE Trail Exit: #{@pos['tradingSymbol']} | Price fallback to entry.")
        return { exit: true, exit_reason: "BreakEven_Trail_#{@a[:pnl_pct]}%" }
      end

      # === 6. Trailing stop adjustment
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
      "risk_manager_#{pos['securityId']}_#{pos['exchangeSegment']}"
    end

    def load_cache
      Rails.cache.read(@key) || { max_pct: @a[:pnl_pct], danger_zone_count: 0 }
    end

    def store_max_pct
      Rails.cache.write(@key, load_cache.merge(max_pct: @a[:pnl_pct]), expires_in: 1.day)
    end

    def store_danger_count(count)
      Rails.cache.write(@key, load_cache.merge(danger_zone_count: count), expires_in: 1.day)
    end

    def reset_danger_count
      Rails.cache.write(@key, load_cache.merge(danger_zone_count: 0), expires_in: 1.day)
    end
  end
end
