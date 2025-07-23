# frozen_string_literal: true

module Orders
  class RiskManager < ApplicationService
    attr_reader :pos, :a, :key, :cache, :max_pct, :danger_count, :trend_against_count, :spot_entry_price

    # --------------------------- CONFIG CONSTANTS --------------------------- #
    STOP_LOSS_PCT    = { stock: 4.0, option: 15.0 }.freeze
    TAKE_PROFIT_PCT  = { stock: 15.0, option: 30.0 }.freeze
    TRAIL_BUFFER_PCT = { stock: 3.0,  option: 5.0 }.freeze
    TIGHT_TRAIL_PCT = { stock: 1.0, option: 3.0 }.freeze

    EMERGENCY_LOSS   = -5000.0
    DANGER_ZONE_MIN  = -2000.0
    DANGER_ZONE_MAX  = -1000.0
    DANGER_ZONE_BARS = 5
    TREND_AGAINST_MAX = 3
    BREAK_EVEN_THRESHOLD_PCT = 10.0 # require at least +10% peak gain for BE rule

    # Spot LTP cache keys for NIFTY and BANKNIFTY indices
    SPOT_INDEX_MAP = {
      'NIFTY' => { segment: 0, id: 13 }, # IDX_I = 0
      'BANKNIFTY' => { segment: 0, id: 25 }
    }.freeze

    def initialize(position, analysis)
      @pos      = position.with_indifferent_access
      @a        = analysis

      @key      = cache_key(@pos)
      @cache    = load_cache

      @max_pct = [@cache[:max_pct], @a[:pnl_pct]].max
      @danger_count        = (@cache[:danger_zone_count] || 0).to_i
      @trend_against_count = (@cache[:trend_against_count] || 0).to_i

      # Load spot_entry_price from analysis or cache
      @spot_entry_price = @a[:spot_entry_price] || @cache[:spot_entry_price]

      return if @spot_entry_price

      if (spot = live_spot_ltp)
        persist_cache(spot_entry_price: spot)
        @spot_entry_price = spot
      end
    end

    def call
      charges = Charges::Calculator.call(@pos, @a)
      net_pnl = @a[:pnl] - charges
      persist_cache(max_pct: @max_pct) if @a[:pnl_pct] > @cache[:max_pct]

      # ① Emergency Exit
      return emergency_exit(net_pnl) if net_pnl <= EMERGENCY_LOSS

      # ② Take Profit
      return take_profit_exit(net_pnl) if net_pnl >= take_profit_threshold

      # ③ Danger Zone Exit
      result = check_danger_zone(net_pnl)
      return result if result

      # ④ Trend Reversal Exit (options only)
      if option_position?
        result = check_trend_reversal
        return result if result
      end

      # ⑤ Trend Break Exit (options only)
      if option_position?
        result = check_trend_break
        return result if result
      end

      # ⑥ Stop Loss
      return stop_loss_exit if percent_stop_hit?

      # ⑦ Break Even Exit
      result = check_break_even
      return result if result

      # ⑧ Trailing Stop Adjustment
      trailing_adjustment
    end

    private

    # === Hard rule helpers ================================================== #

    def emergency_exit(net_pnl)
      reset_danger_count
      notify("🛑 Emergency exit: #{@pos['tradingSymbol']} Net ₹#{net_pnl.round(2)}")
      exit!(:emergency_stop_loss, 'MARKET')
    end

    def take_profit_exit(net_pnl)
      notify("✅ Take profit hit: #{@pos['tradingSymbol']} Net ₹#{net_pnl.round(2)}")
      exit!(:take_profit, 'MARKET')
    end

    def stop_loss_exit
      notify("🛑 Stop Loss Hit: #{pos['tradingSymbol']} | P&L #{@a[:pnl_pct]}%")
      exit!(:stop_loss, 'MARKET')
    end

    def check_danger_zone(net_pnl)
      return nil if net_pnl <= EMERGENCY_LOSS

      if net_pnl.between?(DANGER_ZONE_MIN, DANGER_ZONE_MAX)
        @danger_count += 1
        store_danger_count(@danger_count)
      else
        reset_danger_count
      end

      return unless @danger_count >= DANGER_ZONE_BARS || net_pnl <= DANGER_ZONE_MIN

      reset_danger_count
      notify("⚠️ Danger zone exit: #{@pos['tradingSymbol']}")
      exit!(:danger_zone, 'LIMIT')
    end

    def check_trend_reversal
      trend = trend_for_position
      return nil if trend.blank?

      bias = position_bias(@pos)

      if trend != :neutral && trend != bias
        @trend_against_count += 1
        store_trend_against_count(@trend_against_count)
        notify("🔻 Trend Against Count = #{@trend_against_count}")
      else
        @trend_against_count = 0
        store_trend_against_count(0)
      end

      if @trend_against_count >= TREND_AGAINST_MAX
        reset_trend_against_count
        notify("🔻 Trend Reversal Confirmed — Exiting #{pos['tradingSymbol']} at break-even.")
        return exit!(:trend_reversal_exit, 'MARKET')
      end

      nil
    end

    def check_trend_break
      spot_ltp = live_spot_ltp
      return nil unless spot_ltp

      if trend_broken?(spot_ltp)
        notify("🔻 Spot Trend Break — Exiting #{pos['tradingSymbol']}")
        return exit!(:trend_break_exit, 'MARKET')
      end

      nil
    end

    def check_break_even
      return nil unless @max_pct >= BREAK_EVEN_THRESHOLD_PCT

      if @a[:pnl_pct].abs < 0.5
        notify("📉 Break-even Exit: #{pos['tradingSymbol']} | Max PnL was #{@max_pct}%, now near entry.")
        return exit!(:break_even_trail, 'MARKET')
      end

      nil
    end

    # ------------------------- Trailing SL Adjust ---------------------------

    def trailing_adjustment
      return { exit: false, adjust: false } unless (@a[:pnl_pct]).positive?

      # ① Is the prevailing trend still in our favour?
      trend = trend_for_position
      bias  = position_bias(pos)

      if trend && trend != :neutral && trend != bias
        @trend_against_count += 1
        store_trend_against_count(@trend_against_count)
      else
        @trend_against_count = 0
        store_trend_against_count(0)
      end

      # bail-out if the trend has flipped against us for N consecutive ticks
      if @trend_against_count >= TREND_AGAINST_MAX
        notify("🔻 Trend flipped for #{@trend_against_count} checks — trailing exit.")
        reset_trend_against_count
        return exit!(:trend_trail_exit, 'MARKET')
      end

      trail_buffer_pct =
        @a[:pnl_pct] >= 15.0 ? TIGHT_TRAIL_PCT[:option] : TRAIL_BUFFER_PCT[:option]

      drawdown = @max_pct - @a[:pnl_pct]
      return { exit: false, adjust: false } unless drawdown >= trail_buffer_pct

      new_trigger = (@a[:ltp] * (1 - (trail_buffer_pct / 100.0))).round(2)
      notify("🔁 Trailing SL adjust → new trigger ₹#{new_trigger}")
      {
        exit: false,
        adjust: true,
        adjust_params: { trigger_price: new_trigger }
      }
    end

    # ------------------------- Helper Methods -------------------------------

    def percent_stop_hit?
      thresh = option_position? ? STOP_LOSS_PCT[:option] : STOP_LOSS_PCT[:stock]
      @a[:pnl_pct] <= -thresh
    end

    def exit!(reason, order_type = nil)
      { exit: true, exit_reason: reason.to_s.camelize, order_type: order_type }
    end

    def option_position? = a[:instrument_type] == :option

    def take_profit_threshold
      pct = TAKE_PROFIT_PCT[@a[:instrument_type]]
      @a[:entry_price] * @a[:quantity] * pct / 100.0
    end

    def trend_broken?(spot_ltp)
      return false unless @spot_entry_price

      long = @pos['netQty'].to_i.positive?
      (long && spot_ltp < @spot_entry_price) || (!long && spot_ltp > @spot_entry_price)
    end

    # ------------------------------------------------------------------
    #  🔎  Get the up-to-date intraday trend via Option::ChainAnalyzer
    #      • returns  :bullish / :bearish / :neutral  (or nil on failure)
    # ------------------------------------------------------------------
    def trend_for_position
      underlying = detect_underlying_from_symbol(pos['tradingSymbol'])
      expiry     = extract_expiry_date(pos)
      return nil unless underlying && expiry

      chain = fetch_option_chain(underlying, expiry)
      spot  = live_spot_ltp
      iv_r  = 0.3 # <-- you may still pipe-through the real IV-rank later
      return nil unless chain && spot

      Option::ChainAnalyzer
        .new(chain,
             expiry: expiry,
             underlying_spot: spot,
             iv_rank: iv_r)
        .current_trend # <-- public wrapper, no visibility issues
    end

    def fetch_intraday_trend
      underlying = detect_underlying_from_symbol(pos['tradingSymbol'])
      expiry     = extract_expiry_date(pos)

      # If the context is incomplete we treat the trend as neutral
      return :neutral unless underlying && expiry

      option_chain = fetch_option_chain(underlying, expiry)
      spot_price   = live_spot_ltp
      iv_rank      = 0.3 # (stub until a real IV-rank service is wired)

      # Missing live data ⇒ assume neutral – never raise, never nil
      return :neutral unless option_chain && spot_price

      trend = Option::ChainAnalyzer.new(
                option_chain,
                expiry: expiry,
                underlying_spot: spot_price,
                iv_rank: iv_rank
              ).intraday_trend

      trend.presence || :neutral
    rescue StandardError => e
      Rails.logger.warn { "[RiskManager] fetch_intraday_trend failed – #{e.message}" }
      :neutral
    end

    # ------------------------------------------------------------------
    #  Option-chain helpers (for trend logic)
    # ------------------------------------------------------------------

    # @return [Hash, nil]  live option-chain or nil on failure
    def fetch_option_chain(underlying, expiry)
      cache_key = "rm_chain_#{underlying}_#{expiry}"

      Rails.cache.fetch(cache_key, expires_in: 1.minute) do
        inst = Instrument.find_by!(
          underlying_symbol: underlying,
          segment: 'index', # both NIFTY & BANKNIFTY live here
          exchange: 'NSE'
        )

        # pick the asked expiry (from the position) if present,
        # otherwise fall back to the nearest one
        safe_expiry = if inst.expiry_list.include?(expiry)
                        expiry
                      else
                        inst.expiry_list.first
                      end

        inst.fetch_option_chain(safe_expiry)
      rescue StandardError => e
        Rails.logger.warn { "[RiskManager] option-chain fetch failed – #{e.message}" }
        nil
      end
    end

    def extract_expiry_date(pos)
      raw_date = pos['drvExpiryDate']
      return nil if raw_date.blank? || raw_date == '0001-01-01'

      begin
        Date.parse(raw_date.to_s)
      rescue StandardError
        nil
      end
    end

    def detect_underlying_from_symbol(symbol)
      SPOT_INDEX_MAP.keys.find { |idx| symbol.upcase.include?(idx) }
    end

    def position_bias(pos)
      sym = pos[:tradingSymbol].to_s.upcase
      long = pos[:netQty].to_i.positive?

      if sym.include?('CE')      then long ? :bullish : :bearish
      elsif sym.include?('PE')   then long ? :bearish : :bullish
      else
        :neutral
      end
    end

    def trend_broken?(spot_ltp)
      return false unless @spot_entry_price

      long = pos[:netQty].to_i.positive?
      (long && spot_ltp <  @spot_entry_price) ||
        (!long && spot_ltp > @spot_entry_price)
    end

    def cache_key(pos)
      "risk_manager_#{pos['securityId']}_#{pos['exchangeSegment']}"
    end

    def load_cache
      Rails.cache.read(@key) || {
        max_pct: @a[:pnl_pct],
        danger_zone_count: 0,
        trend_against_count: 0,
        spot_entry_price: nil
      }
    end

    def persist_cache(new_values = {})
      Rails.cache.write(@key, load_cache.merge(new_values), expires_in: 1.day)
    end

    def store_danger_count(count)
      persist_cache(danger_zone_count: count)
    end

    def store_trend_against_count(count)
      persist_cache(trend_against_count: count)
    end

    def reset_danger_count
      persist_cache(danger_zone_count: 0)
    end

    def reset_trend_against_count
      persist_cache(trend_against_count: 0)
    end

    def live_spot_ltp
      idx = SPOT_INDEX_MAP.detect { |k, _| pos[:tradingSymbol].to_s.include?(k) }&.last
      MarketCache.read_ltp(idx[:segment], idx[:id]) if idx
    end
  end
end
