# frozen_string_literal: true

module Orders
  class RiskManager < ApplicationService
    STOP_LOSS_PCT    = { stock: 7.5, option: 25.0 }.freeze
    TAKE_PROFIT_PCT  = { stock: 15.0, option: 35.0 }.freeze
    TRAIL_BUFFER_PCT = { stock: 3.0,  option: 10.0 }.freeze

    EMERGENCY_LOSS   = -5000.0
    DANGER_ZONE_MIN  = -1500.0
    DANGER_ZONE_MAX  = -750.0
    DANGER_ZONE_BARS = 5

    # Spot LTP cache keys for NIFTY and BANKNIFTY indices
    SPOT_INDEX_MAP = {
      'NIFTY' => { segment: 0, id: 13 },        # IDX_I = 0
      'BANKNIFTY' => { segment: 0, id: 25 }
    }.freeze

    def initialize(position, analysis)
      @pos      = position.with_indifferent_access
      @a        = analysis
      @key      = cache_key(@pos)
      @cache    = load_cache
      @max_pct  = @cache[:max_pct] || @a[:pnl_pct]
      @danger_count = @cache[:danger_zone_count] || 0
    end

    def call
      charges = Charges::Calculator.call(@pos, @a)
      net_pnl = @a[:pnl] - charges
      is_option = @a[:instrument_type] == :option

      store_max_pct if @a[:pnl_pct] > @max_pct

      # === 1. Take Profit
      if net_pnl >= take_profit_threshold
        notify("✅ TP Hit: #{@pos['tradingSymbol']} | Net ₹#{net_pnl.round(2)}")
        return { exit: true, exit_reason: "TakeProfit_#{net_pnl}" }
      end

      # === 2. Danger Zone Buffer
      if net_pnl <= DANGER_ZONE_MAX && net_pnl > DANGER_ZONE_MIN
        @danger_count += 1
        store_danger_count(@danger_count)
      else
        reset_danger_count
      end

      if @danger_count >= DANGER_ZONE_BARS || net_pnl <= DANGER_ZONE_MIN
        reset_danger_count
        notify("⚠️ Danger Zone Exit: #{@pos['tradingSymbol']} | Net ₹#{net_pnl.round(2)}")
        return { exit: true, exit_reason: "DangerZone_#{net_pnl}", order_type: :limit }
      end

      # === 3. Emergency Cutoff
      if net_pnl <= EMERGENCY_LOSS
        reset_danger_count
        notify("🛑 Emergency SL: #{@pos['tradingSymbol']} | Net ₹#{net_pnl.round(2)}")
        return { exit: true, exit_reason: "EmergencyStopLoss_#{net_pnl}" }
      end

      # === 4. SL Adaptation (Options Only)
      if is_option
        spot_ltp = live_spot_ltp
        if spot_ltp && trend_broken?(spot_ltp)
          notify("🔻 Trend Broken — Tight Exit: #{@pos['tradingSymbol']}")
          return { exit: true, exit_reason: 'TrendBreakExit' }
        end

        if spot_ltp && retracing_but_uptrend?(spot_ltp)
          # Loosen SL by 5% to allow retracement
          loosened_sl = STOP_LOSS_PCT[:option] + 5.0
          if @a[:pnl_pct] <= -loosened_sl
            notify("🛑 Loosened % SL Hit (Retrace Allow): #{@pos['tradingSymbol']} | P&L #{@a[:pnl_pct]}%")
            return { exit: true, exit_reason: "LoosenedStopLoss_#{@a[:pnl_pct]}%" }
          end
        elsif @a[:pnl_pct] <= -STOP_LOSS_PCT[:option]
          notify("🛑 % SL Hit: #{@pos['tradingSymbol']} | P&L #{@a[:pnl_pct]}%")
          return { exit: true, exit_reason: "StopLoss_#{@a[:pnl_pct]}%" }
        end
      elsif @a[:pnl_pct] <= -STOP_LOSS_PCT[:stock]
        # === 5. % Stop-loss for Stocks
        notify("🛑 % SL Hit: #{@pos['tradingSymbol']} | P&L #{@a[:pnl_pct]}%")
        return { exit: true, exit_reason: "StopLoss_#{@a[:pnl_pct]}%" }
      end

      # === 6. Break-even Trail
      if @a[:pnl_pct] >= 40.0 && @a[:ltp] <= @a[:entry_price]
        notify("📉 BE Trail Exit: #{@pos['tradingSymbol']} | Price fallback to entry.")
        return { exit: true, exit_reason: 'BreakEven_Trail' }
      end

      # === 7. Trailing Stop Adjustment
      drawdown = @max_pct - @a[:pnl_pct]
      buffer_pct = TRAIL_BUFFER_PCT[@a[:instrument_type]]

      if @a[:pnl_pct].positive? && drawdown >= buffer_pct
        new_trigger = (@a[:ltp] * (1 - (buffer_pct / 100.0))).round(2)
        return {
          adjust: true,
          adjust_params: { trigger_price: new_trigger }
        }
      end

      { exit: false, adjust: false }
    end

    private

    def take_profit_threshold
      pct = TAKE_PROFIT_PCT[@a[:instrument_type]]
      @a[:entry_price] * @a[:quantity] * pct / 100.0
    end

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

    def live_spot_ltp
      symbol = @pos['tradingSymbol'].to_s
      index_info = SPOT_INDEX_MAP.find { |k, _| symbol.include?(k) }&.last
      return nil unless index_info

      MarketCache.read_ltp(index_info[:segment], index_info[:id])
    end

    def trend_broken?(spot_ltp)
      # Basic logic: if long and spot < entry, or short and spot > entry
      long = @pos['netQty'].to_i.positive?
      (long && spot_ltp < @a[:entry_price]) || (!long && spot_ltp > @a[:entry_price])
    end

    def retracing_but_uptrend?(spot_ltp)
      long = @pos['netQty'].to_i.positive?
      long && spot_ltp > @a[:entry_price] && @a[:ltp] < @a[:entry_price]
    end
  end
end
