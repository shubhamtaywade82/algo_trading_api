# frozen_string_literal: true

module AlertProcessors
  # Processes TradingView alerts for INDEX instruments (e.g. NIFTY / BANKNIFTY).
  #
  #  Flow ────────────────────────────────────────────────────────────────────
  #   1.  Validate the incoming signal against current positions
  #   2.  Pick the nearest-expiry contract
  #   3.  Pull live option-chain + minimal historical candles
  #   4.  Run Option::ChainAnalyzer to shortlist viable strikes
  #   5.  Select the first strike you can actually afford
  #   6.  Look-up the derivative (security_id) in the DB
  #   7.  Build & (optionally) place the order
  #   8.  Update + log the result
  #
  #  Public contract ─────────────────────────────────────────────────────────
  #   • Constants:  ATM_RANGE_PERCENT, MIN_DELTA, MIN_OI_THRESHOLD, MIN_PREMIUM
  #   • Class inherits from Base and exposes    #call
  #
  class Index < Base
    # ──────────────────────────────────────────────────────────────────
    # Tunables / thresholds
    # ──────────────────────────────────────────────────────────────────
    ATM_RANGE_PERCENT = 0.01
    MIN_DELTA         = 0.30
    MIN_OI_THRESHOLD  = 50_000
    MIN_PREMIUM       = ENV.fetch('MIN_OPTION_PREMIUM', 5).to_f

    # ─── RR % from entry price
    DEFAULT_STOP_LOSS_PCT  = 0.18      # widen SL by default (~18 %)
    DEFAULT_TARGET_PCT     = 0.30      # aim for ~30 % (RR ≈ 1 : 1.7)
    DEFAULT_TRAIL_JUMP_PCT = 0.06      # trail every ~6 % move in price
    USE_SUPER_ORDER        = ENV.fetch('USE_SUPER_ORDER', 'true') == 'true'

    # ──────────────────────────────────────────────────────────────────
    # Capital-aware deployment policy
    # ──────────────────────────────────────────────────────────────────
    # Bands are inclusive upper-bounds. Tweak as you like.
    CAPITAL_BANDS = [
      { upto: 75_000, alloc_pct: 0.30, risk_per_trade_pct: 0.050, daily_max_loss_pct: 0.050 }, # small a/c (≈ ₹50k)
      { upto: 150_000,  alloc_pct: 0.25, risk_per_trade_pct: 0.035, daily_max_loss_pct: 0.060 }, # ≈ ₹1L
      { upto: 300_000,  alloc_pct: 0.20, risk_per_trade_pct: 0.030, daily_max_loss_pct: 0.060 }, # ≈ ₹2–3L
      { upto: Float::INFINITY, alloc_pct: 0.20, risk_per_trade_pct: 0.025, daily_max_loss_pct: 0.050 }
    ].freeze

    # Entry-point that the Sidekiq job / controller calls
    # ----------------------------------------------------------------
    def call
      notify("📥 [#{alert[:signal_type].upcase}] Index Alert ##{alert.id} received")
      log :info, '▼▼▼  START  ▼▼▼'
      return skip!(:validation_failed) unless pre_trade_validation

      execute_trade_plan!
      alert.update!(status: :processed)
    rescue StandardError => e
      alert.update!(status: :failed, error_message: e.message)
      log :error, "#{e.class} – #{e.message}\n#{e.backtrace.first(8).join("\n")}"
    ensure
      log :info, '▲▲▲  END  ▲▲▲'
    end

    # ----------------------------------------------------------------
    private

    # ------------------------------------------------------------------
    #           0. Signal-→-Intent helpers  (NEW / CHANGED)
    # ------------------------------------------------------------------
    #
    # • *_entry  ⇒ BUY   the option (Call for long_entry, Put for short_entry)
    # • *_exit   ⇒ SELL  the option that was previously bought
    #
    SIGNAL_TO_OPTION = {
      'long_entry' => :ce,
      'long_exit' => :ce,
      'short_entry' => :pe,
      'short_exit' => :pe
    }.freeze

    SIGNAL_TO_SIDE = {
      'long_entry' => 'BUY',
      'short_entry' => 'BUY',
      'long_exit' => 'SELL',
      'short_exit' => 'SELL'
    }.freeze

    # ----------------------------------------------------------------

    # -- Main orchestration ---------------------------------------------------
    def execute_trade_plan!
      expiry   = instrument.expiry_list.first
      chain    = safe_fetch_option_chain(expiry)
      option   = SIGNAL_TO_OPTION.fetch(alert[:signal_type]) # :ce / :pe
      iv_rank  = iv_rank_for(chain)
      analyzer = build_analyzer(chain, expiry, iv_rank)

      result = analyzer.analyze(
        strategy_type: alert[:strategy_type],
        signal_type: option
      )

      log :info, "Spot bias  : #{result[:trend]&.upcase}  (ADX #{result[:adx]&.round(1)})"
      log :info, "Momentum   : #{result[:momentum]}"
      log :info, "Proceed? => #{result[:proceed]}"

      unless result[:proceed]
        skip_reason = build_detailed_skip_reason(result)
        return skip!(skip_reason)
      end

      log_result_summary(result)
      selected = result[:selected]
      ranked   = result[:ranked]
      return skip!(:no_viable_strikes) unless selected

      # Check affordability of selected first
      fallback = nil
      strike = if strike_affordable?(selected, expiry, option)
                 log :info, "✅ Selected strike is affordable (≥1 lot): #{format_strike(selected)}"
                 selected
               else
                 fallback = pick_affordable_strike(ranked, expiry, option)
                 if fallback && strike_affordable?(fallback, expiry, option)
                   log :info, "⚠️ Selected strike not affordable. Fallback chosen: #{format_strike(fallback)}"
                   fallback
                 else
                   log :warn, '🚫 No affordable strike found after fallback attempt.'
                   nil
                 end
               end

      if strike
        log :info, "🎯 Proceeding with strike: #{format_strike(strike)}"
      else
        log :warn,
            "❌ No strike available after affordability checks. Selected=#{format_strike(selected)}, " \
            "Fallback=#{format_strike(fallback)}"
        return skip!(:no_affordable_strike)
      end

      derivative = fetch_derivative(strike, expiry, option)
      unless derivative
        log :error,
            "❌ Derivative missing for strike #{format_strike(strike)} (expiry=#{expiry}, option=#{option.to_s.upcase}). " \
            "Consider re-importing instrument derivatives."
        return skip!(:no_derivative)
      end

      quantity = calculate_quantity(strike, derivative.lot_size)
      if quantity.zero?
        log :warn, "🚫 Calculated quantity is 0 for #{format_strike(strike)}"
        return skip!(:invalid_quantity)
      end

      if USE_SUPER_ORDER
        order = build_super_order_payload(strike, derivative, quantity)
        return skip!(:ltp_unavailable) unless order

        ENV['PLACE_ORDER'] == 'true' ? place_super_order!(order) : dry_run(order)
      else
        order = build_order_payload(strike, derivative, quantity) # ← legacy 1-leg
        ENV['PLACE_ORDER'] == 'true' ? place_order!(order) : dry_run(order)
      end
    end

    # -- Validation helpers ---------------------------------------------------
    def pre_trade_validation
      return false unless daily_loss_guard_ok?

      case alert[:signal_type]
      when 'long_entry'
        # close_opposite!(:pe)  # Close any PE before entering CE
        true # Always allow new CE entry
      when 'short_entry'
        # close_opposite!(:ce)  # Close any CE before entering PE
        true # Always allow new PE entry
      when 'long_exit'
        exit_position!(:ce)
        false
      when 'short_exit'
        exit_position!(:pe)
        false
      else
        true
      end
    end

    def ensure_no_position!(type)
      already = type == :ce ? open_long_ce_position? : open_long_pe_position?
      return true unless already

      reason = "existing #{type.upcase} position"
      log :info, "skip – #{reason}"
      alert.update!(status: :skipped, error_message: reason)
      false
    end

    # -- Option-chain / analyzer ---------------------------------------------
    def safe_fetch_option_chain(expiry)
      instrument.fetch_option_chain(expiry)
    rescue StandardError => e
      raise "option-chain fetch failed (#{expiry}) – #{e.message}"
    end

    def iv_rank_for(chain)
      Option::ChainAnalyzer.estimate_iv_rank(chain)
    end

    def option_ltp(derivative)
      # the Derivative model already wraps a Dhan quote call; fallback kept for safety
      derivative.ltp || Dhanhq::API::Quote.ltp(derivative.security_id)
    rescue StandardError
      nil
    end

    def build_analyzer(chain, expiry, iv_rank)
      Option::ChainAnalyzer.new(
        chain,
        expiry: expiry,
        underlying_spot: chain[:last_price] || ltp,
        iv_rank: iv_rank,
        historical_data: historical_data
      )
    end

    def historical_data
      Option::HistoricalDataFetcher.for_strategy(instrument, strategy_type: alert[:strategy_type])
    end

    def determine_atm_strike(chain)
      spot = chain[:last_price].to_f
      chain[:oc].keys.map(&:to_f).min_by { |s| (s - spot).abs }
    end

    # -- Strike / derivative selection ---------------------------------------
    def strike_affordable?(strike, expiry, option)
      return false unless strike

      check_affordability_and_log(strike, expiry, option)
    end

    def pick_affordable_strike(ranked, expiry, option)
      ranked.detect { |s| strike_affordable?(s, expiry, option) } || ranked.min_by { |s| s[:last_price] }
    end

    def fetch_derivative(strike, expiry, dir)
      derivative = instrument.derivatives.find_by(
        strike_price: strike[:strike_price],
        expiry_date: expiry,
        option_type: dir.to_s.upcase
      )
      if derivative
        log :info,
            "🧾 Derivative found → security_id=#{derivative.security_id}, lot=#{derivative.lot_size}, " \
            "segment=#{derivative.exchange_segment}"
      else
        log :warn,
            "⚠️ Derivative lookup failed for strike #{strike[:strike_price]} (expiry=#{expiry}, option=#{dir.to_s.upcase})."
      end
      derivative
    end

    # ------------------------------------------------------------------
    # Build stop-loss / target / trail using ATR%.
    # Fallback to the fixed defaults when ATR% is unavailable.
    # ------------------------------------------------------------------
    def rrules_for(entry_price)
      atr_pct = current_atr_pct

      if atr_pct&.positive?
        # Empirical mapping for 0 Δ.4 near-ATM options:
        #   • option_move ≈ atr_pct × 4
        #   • we risk ½ of that move, aim for 1×, trail at ¼
        sl_pct     = (atr_pct * 2).clamp(DEFAULT_STOP_LOSS_PCT, 0.25)   # 0.5 × exp move
        tp_pct     = (atr_pct * 4).clamp(DEFAULT_TARGET_PCT, 0.60)      # 1.0 × exp move
        trail_pct  = atr_pct.clamp(DEFAULT_TRAIL_JUMP_PCT, 0.15)        # 0.25 × exp move
      else
        sl_pct = DEFAULT_STOP_LOSS_PCT
        tp_pct = DEFAULT_TARGET_PCT
        trail_pct = DEFAULT_TRAIL_JUMP_PCT
      end

      {
        stop_loss: PriceMath.round_tick(entry_price * (1 - sl_pct)),
        target: PriceMath.round_tick(entry_price * (1 + tp_pct)),
        trail_jump: PriceMath.round_tick(entry_price * trail_pct)
      }
    end

    # -- Order building & execution ------------------------------------------
    def build_order_payload(strike, derivative, quantity)
      {
        transactionType: SIGNAL_TO_SIDE.fetch(alert[:signal_type]), # BUY / SELL
        orderType: alert[:order_type].to_s.upcase, # MARKET / LIMIT
        productType: Dhanhq::Constants::MARGIN,
        validity: Dhanhq::Constants::DAY,
        securityId: derivative.security_id,
        exchangeSegment: derivative.exchange_segment,
        quantity: quantity
      }
    end

    def build_super_order_payload(strike, derivative, quantity)
      live = option_ltp(derivative)
      unless live
        log :error, "LTP fetch failed for #{derivative.security_id}"
        return
      end

      rr = rrules_for(live) || rrules_for(strike[:last_price])
      pp rr, live
      {
        transactionType: SIGNAL_TO_SIDE.fetch(alert[:signal_type]), # BUY
        exchangeSegment: derivative.exchange_segment,
        productType: Dhanhq::Constants::MARGIN,
        orderType: alert[:order_type].to_s.upcase, # MARKET/LIMIT
        securityId: derivative.security_id,
        quantity: quantity,
        # price: strike[:last_price].round(2), # entry
        targetPrice: rr[:target],
        stopLossPrice: rr[:stop_loss],
        trailingJump: rr[:trail_jump]
      }
    end

    def place_order!(params)
      resp = Dhanhq::API::Orders.place(params)
      log :info, "order placed  → #{resp}"
      alert.update!(error_message: "orderId #{resp['orderId']}")

      notify(<<~MSG.strip, tag: 'ORDER')
        ✅ Order Placed – Alert ##{alert.id}
        • Symbol: #{instrument.symbol_name}
        • Type: #{params[:transactionType]}
        • Qty: #{params[:quantity]}
        • Order ID: #{resp['orderId']}
      MSG
    end

    def place_super_order!(params)
      resp = Dhanhq::API::SuperOrders.place(params)
      log :info, "super-order placed → #{resp}"
      alert.update!(error_message: "SO #{resp['orderId']}")

      notify(<<~MSG.strip, tag: 'SUPER')
        🚀 Super-Order Placed – Alert ##{alert.id}
        • Symbol : #{instrument.symbol_name}
        • Qty    : #{params[:quantity]}
        • Entry  : ₹#{params[:price]}
        • SL     : ₹#{params[:stopLossPrice]}
        • TP     : ₹#{params[:targetPrice]}
        • Trail  : ₹#{params[:trailingJump]}
        • SO-ID  : #{resp['orderId']}
      MSG
    end

    # ────────────────────────────────────────────────────────────
    # Latest 5-minute ATR% that Market::AnalysisUpdater wrote.
    # Returns nil if no fresh row (<10 min old) exists.
    # ────────────────────────────────────────────────────────────
    def current_atr_pct
      row = IntradayAnalysis.for(instrument.underlying_symbol, '5m')
      return nil unless row && row.calculated_at > 10.minutes.ago

      row.atr_pct.to_f # eg 0.0082  ( = 0.82 %)
    end

    def dry_run(params)
      log :info, "dry-run order → #{params}"
      alert.update!(
        status: :skipped,
        error_message: 'PLACE_ORDER disabled',
        metadata: { simulated_order: params } # assuming you have a JSONB column
      )
      notify(<<~MSG.strip, tag: 'DRYRUN')
        💡 DRY-RUN (PLACE_ORDER=false) – Alert ##{alert.id}
        • Symbol: #{instrument.symbol_name}
        • Type: #{params[:transactionType]}
        • Qty: #{params[:quantity]}
      MSG
    end

    # -- Capital-aware deployment policy --------------------------------------
    def deployment_policy(balance = available_balance.to_f)
      band = CAPITAL_BANDS.find { |b| balance <= b[:upto] } || CAPITAL_BANDS.last
      # Allow env overrides (optional)
      alloc = ENV['ALLOC_PCT']&.to_f || band[:alloc_pct]
      r_pt  = ENV['RISK_PER_TRADE_PCT']&.to_f || band[:risk_per_trade_pct]
      d_ml  = ENV['DAILY_MAX_LOSS_PCT']&.to_f || band[:daily_max_loss_pct]

      { alloc_pct: alloc, risk_per_trade_pct: r_pt, daily_max_loss_pct: d_ml }
    end

    # Get effective SL% used for risk math. Prefer ATR-adaptive; fallback to default.
    def effective_sl_pct(entry_price = nil)
      rr = rrules_for(entry_price || 100) # entry price not strictly needed for pct
      # Convert price targets back to % if needed, else just return defaults when ATR missing.
      if rr && (entry_price && entry_price.to_f.positive?)
        sl_pct = 1.0 - (rr[:stop_loss].to_f / entry_price.to_f)
        return sl_pct.clamp(0.02, 0.35) if sl_pct.finite? && sl_pct.positive?
      end
      DEFAULT_STOP_LOSS_PCT # 0.18 by default
    end

    # Daily loss guard - prevents new entries when daily loss exceeds band limit
    def daily_loss_guard_ok?
      policy = deployment_policy
      max_loss = available_balance.to_f * policy[:daily_max_loss_pct]
      loss_today = daily_loss_today
      # Both loss_today and max_loss are negative, so we compare absolute values
      return true if loss_today.to_f.abs < max_loss.abs

      log :warn, "⛔️ Daily loss guard hit: #{PriceMath.round_tick(loss_today)} >= max #{PriceMath.round_tick(max_loss)}"
      true # false
    end

    # Calculate today's realized loss from positions
    def daily_loss_today
      Rails.cache.fetch("daily_loss:#{Date.current}", expires_in: 1.hour) do
        positions = Dhanhq::API::Portfolio.positions
        positions.sum do |pos|
          realized_pnl = pos['realizedProfit'].to_f
          realized_pnl.negative? ? realized_pnl : 0
        end
      end
    end

    # -- Sizing ---------------------------------------------------------------
    def calculate_quantity(strike, lot_size)
      lot_size = lot_size.to_i
      price    = strike[:last_price].to_f
      strike_info = "Strike #{strike[:strike_price]} | Last: #{strike[:last_price]}"

      if lot_size.zero? || price <= 0
        log :error, "❗ Invalid sizing inputs (lot=#{lot_size}, price=#{price}) for #{instrument.id} (#{strike_info})"
        return 0
      end

      balance     = available_balance.to_f
      policy      = deployment_policy(balance)
      alloc_cap   = (balance * policy[:alloc_pct]) # ₹ you may deploy in this trade
      per_lot_cost  = price * lot_size

      # If you can't afford a lot at all, bail early
      if per_lot_cost > balance
        log_insufficient_margin(strike_info, per_lot_cost, balance)
        return 0
      end

      # 1) Allocation constraint: how many lots fit inside alloc_cap?
      max_lots_by_alloc = (alloc_cap / per_lot_cost).floor

      # 2) Risk constraint: cap lots so that (lots * per_lot_risk) <= risk_per_trade_cap
      #    per_lot_risk ≈ premium * lot_size * SL%
      #    Use ATR-adaptive SL% if available.
      sl_pct         = effective_sl_pct(price)
      per_lot_risk   = per_lot_cost * sl_pct
      risk_cap       = balance * policy[:risk_per_trade_pct]
      max_lots_by_risk = per_lot_risk.positive? ? (risk_cap / per_lot_risk).floor : 0

      # 3) Affordability constraint: you must at least afford 1 lot
      max_lots_by_afford = (balance / per_lot_cost).floor

      # The final lots are bounded by all three constraints.
      lots = [max_lots_by_alloc, max_lots_by_risk, max_lots_by_afford].min

      # Graceful 1-lot allowance if alloc-bound is 0 but you still can afford & risk allows
      if lots.zero? && per_lot_cost <= balance && per_lot_risk <= risk_cap
        lots = 1
        log :info, "💡 Alloc-band too tight for >0 lots, allowing 1 lot given affordability & risk OK. (#{strike_info})"
      end

      if lots.zero?
        msg = "No size fits constraints. alloc_cap=₹#{PriceMath.round_tick(alloc_cap)}, " \
              "risk_cap=₹#{PriceMath.round_tick(risk_cap)}, per_lot_cost=₹#{PriceMath.round_tick(per_lot_cost)}, " \
              "per_lot_risk=₹#{PriceMath.round_tick(per_lot_risk)}"
        log :warn, "🚫 Sizing → #{msg}"
        return 0
      end

      total_cost = lots * per_lot_cost
      total_risk = lots * per_lot_risk

      log :info, "✅ Sizing decided: #{lots} lot(s) (qty ~ #{lots * lot_size}). " \
                 "Alloc cap: ₹#{PriceMath.round_tick(alloc_cap)}, Risk cap: ₹#{PriceMath.round_tick(risk_cap)}. " \
                 "Per-lot cost: ₹#{PriceMath.round_tick(per_lot_cost)}, Per-lot risk: ₹#{PriceMath.round_tick(per_lot_risk)}. " \
                 "Total cost: ₹#{PriceMath.round_tick(total_cost)}, Total risk: ₹#{PriceMath.round_tick(total_risk)}. " \
                 "(SL%≈#{(sl_pct * 100).round(1)}%)"

      lots * lot_size
    end

    # -- Positions helpers ----------------------------------------------------
    def open_long_ce_position?
      open_long_position?(ce_security_ids)
    end

    def open_long_pe_position?
      open_long_position?(pe_security_ids)
    end

    def open_long_position?(sec_ids)
      dhan_positions.any? { |p| p['positionType'] == 'LONG' && sec_ids.include?(p['securityId'].to_s) }
    end

    def ce_security_ids
      @ce_security_ids ||= instrument.derivatives.where(option_type: 'CE').pluck(:security_id).map(&:to_s)
    end

    def pe_security_ids
      @pe_security_ids ||= instrument.derivatives.where(option_type: 'PE').pluck(:security_id).map(&:to_s)
    end

    # -- Exit helpers ---------------------------------------------------------
    def exit_position!(type)
      ids = type == :ce ? ce_security_ids : pe_security_ids
      positions = dhan_positions.select { |p| p['positionType'] == 'LONG' && ids.include?(p['securityId'].to_s) }
      return skip!("no #{type.upcase} position to exit") if positions.empty?

      positions.each do |pos|
        Dhanhq::API::Orders.place(
          transactionType: 'SELL',
          orderType: 'MARKET',
          productType: Dhanhq::Constants::MARGIN,
          validity: Dhanhq::Constants::DAY,
          securityId: pos['securityId'],
          exchangeSegment: pos['exchangeSegment'],
          quantity: pos['quantity']
        )
        log :info, "closed #{type.upcase} ⇒ #{pos.slice('securityId', 'quantity')}"
        notify("📤 Exited #{type.upcase} position(s) for Alert ##{alert.id}", tag: 'EXIT')
      end
      alert.update!(status: :processed, error_message: "exited #{type.upcase}")
      false
    end

    # Immediately closes all open opposite-side positions
    def close_opposite!(type)
      ids = type == :ce ? ce_security_ids : pe_security_ids
      positions = dhan_positions.select { |p| p['positionType'] == 'LONG' && ids.include?(p['securityId'].to_s) }
      return if positions.empty?

      positions.each do |pos|
        Dhanhq::API::Orders.place(
          transactionType: 'SELL',
          orderType: 'MARKET',
          productType: Dhanhq::Constants::MARGIN,
          validity: Dhanhq::Constants::DAY,
          securityId: pos['securityId'],
          exchangeSegment: pos['exchangeSegment'],
          quantity: pos['quantity']
        )
        log :info, "Flipped & closed #{type.upcase} ⇒ #{pos.slice('securityId', 'quantity')}"
        notify("↔️ Closed opposite #{type.upcase} position(s) before new entry (Alert ##{alert.id})", tag: 'FLIP')
      end
    end

    # -- Utility --------------------------------------------------------------
    def direction(action)
      action.to_s.casecmp('buy').zero? ? :ce : :pe
    end

    def skip!(reason)
      alert.update!(status: :skipped, error_message: reason.to_s)
      log :info, "skip – #{reason}"

      notify("⛔️ Skipped Index Alert ##{alert.id} – #{reason.to_s.humanize}", tag: 'SKIP')
      false
    end

    def log(level, msg)
      Rails.logger.send(level, "[Index #{alert.id}] #{msg}")
    end

    def log_result_summary(result)
      log :info, "Analyzer Result → Trend: #{result[:trend]}, Signal: #{result[:signal_type]}"
      log :info, "Selected: #{format_strike(result[:selected])}"
      ranked_list = result[:ranked].map { |r| format_strike(r) }.join("\n")
      log :info, "Top Ranked Options:\n#{ranked_list}"

      notify(<<~MSG.strip, tag: 'ANALYZER')
        🧠 Analyzer Result – Alert ##{alert.id}
        • Trend: #{result[:trend]}
        • Signal: #{result[:signal_type]}
        • Selected: #{format_strike(result[:selected])}
      MSG
    end

    def format_strike(strike)
      return 'nil' unless strike

      "Strike #{strike[:strike_price]} | Last: #{strike[:last_price]} | IV: #{strike[:iv]} | OI: #{strike[:oi]} | Δ: #{strike.dig(
        :greeks, :delta
      )}"
    end

    def log_pretty_error(error)
      log :error, "🚨 #{error.class}: #{error.message}\n#{error.backtrace.first(5).join("\n")}"
    end

    def lot_size_for(expiry, option_type)
      @lot_sizes ||= {}
      key = "#{expiry}-#{option_type}"
      @lot_sizes[key] ||= begin
        derivative = instrument.derivatives.find_by(
          expiry_date: expiry,
          option_type: option_type.to_s.upcase
        )
        if derivative.nil?
          log :warn, "⚠️ Could not find derivative for memoized lot size (#{expiry}, #{option_type.upcase})"
          0
        else
          derivative.lot_size
        end
      end
    end

    def check_affordability_and_log(strike, expiry, option)
      lot_size = lot_size_for(expiry, option)
      strike_info = "Strike #{strike[:strike_price]} | Last: #{strike[:last_price]}"

      if lot_size.zero?
        log :error, "❗ Invalid lot size (0) for instrument: #{instrument.id} (#{strike_info})"
        return false
      end

      per_lot_cost = strike[:last_price].to_f * lot_size

      if per_lot_cost > available_balance
        log_insufficient_margin(strike_info, per_lot_cost, available_balance)
        false
      else
        log :info,
            "✅ Can afford at least 1 lot. (#{strike_info}) Required: ₹#{PriceMath.round_tick(per_lot_cost)}, Available: ₹#{PriceMath.round_tick(available_balance)}."
        true
      end
    end

    def log_insufficient_margin(strike_info, per_lot_cost, available_balance)
      shortfall = per_lot_cost - available_balance
      log :warn,
          "🚫 Insufficient margin. (#{strike_info}) Required for 1 lot: ₹#{PriceMath.round_tick(per_lot_cost)}, " \
          "Available: ₹#{PriceMath.round_tick(available_balance)}, Shortfall: ₹#{PriceMath.round_tick(shortfall)}. No order placed."
    end

    def build_detailed_skip_reason(result)
      reasons = result[:reasons] || [result[:reason]]
      validation_details = result[:validation_details] || {}

      # Build the main reason
      main_reason = reasons.join('; ')

      # Add detailed context
      details = []

      # IV Rank details
      if validation_details[:iv_rank]
        iv_info = validation_details[:iv_rank]
        details << "IV Rank: #{iv_info[:current_rank]&.round(3)} (Range: #{iv_info[:min_rank]}-#{iv_info[:max_rank]})"
      end

      # Theta Risk details
      if validation_details[:theta_risk]
        theta_info = validation_details[:theta_risk]
        details << "Theta Risk: #{theta_info[:current_time]} (Expiry: #{theta_info[:expiry_date]}, Hours left: #{theta_info[:hours_left]})"
      end

      # ADX details
      if validation_details[:adx]
        adx_info = validation_details[:adx]
        details << "ADX: #{adx_info[:current_value]&.round(2)} (Min: #{adx_info[:min_value]})"
      end

      # Trend/Momentum details
      if validation_details[:trend_momentum]
        tm_info = validation_details[:trend_momentum]
        details << "Trend: #{tm_info[:trend][:current_trend]} (Signal: #{tm_info[:trend][:signal_type]})" if tm_info[:trend]
        details << "Momentum: #{tm_info[:momentum][:current_momentum]} (Signal: #{tm_info[:momentum][:signal_type]})" if tm_info[:momentum]
        if tm_info[:trend_mismatch]
          details << "Trend Mismatch: #{tm_info[:trend_mismatch][:signal_type]} vs #{tm_info[:trend_mismatch][:current_trend]}"
        end
      end

      # Strike Selection details
      if validation_details[:strike_selection]
        ss_info = validation_details[:strike_selection]
        details << "Strikes: #{ss_info[:filtered_count]}/#{ss_info[:total_strikes]} passed filters"

        # Add strike guidance if available
        if ss_info[:strike_guidance] && ss_info[:strike_guidance][:recommended_strikes]&.any?
          guidance = ss_info[:strike_guidance]
          details << "Recommended: #{Array(guidance[:recommended_strikes]).join(', ')}"
          details << "Explanation: #{guidance[:explanation]}" if guidance[:explanation].present?
        end

        if ss_info[:filters_applied]&.any?
          filters = ss_info[:filters_applied]
          formatted_filters = Array(filters).map do |filter|
            if filter.is_a?(Hash)
              reasons = Array(filter[:reasons]).join(', ')
              "#{filter[:strike_price]} (#{reasons})"
            else
              filter
            end
          end
          details << "Filter Details: #{formatted_filters.join('; ')}"
        end
      end

      # Combine all information
      full_reason = main_reason
      full_reason += " | Details: #{details.join(' | ')}" if details.any?

      # Log the detailed reason for debugging
      log :warn, "Signal skipped - #{full_reason}"

      full_reason
    end
  end
end
