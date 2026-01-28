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

    # Entry-point that the Sidekiq job / controller calls
    # ----------------------------------------------------------------
    def call
      notify("📥 [#{alert[:signal_type].upcase}] Index Alert ##{alert.id} received")
      log :info, '▼▼▼  START  ▼▼▼'
      return skip!(:validation_failed) unless pre_trade_validation

      execute_trade_plan!
      alert.update!(status: :processed) unless alert.status == 'skipped'
    rescue StandardError => e
      # Handle market-closed errors by skipping instead of failing
      if e.message.include?('Market is closed')
        log :warn, "Market is closed – skipping alert: #{e.message}"
        skip!(:market_closed)
      # Handle LTP fetch failures gracefully
      elsif e.message.include?('Failed to fetch LTP')
        log :warn, "LTP unavailable – skipping alert: #{e.message}"
        skip!(:ltp_unavailable)
      else
        alert.update!(status: :failed, error_message: e.message)
        log :error, "#{e.class} – #{e.message}\n#{e.backtrace.first(8).join("\n")}"
      end
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
        skip_reason = IndexSkipReasonBuilder.build(result)
        log :warn, "Signal skipped - #{skip_reason}"
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
            'Consider re-importing instrument derivatives.'
        return skip!(:no_derivative)
      end

      sizing = quantity_calculator_result(strike, derivative.lot_size)
      quantity = sizing[:quantity]
      if quantity.zero?
        log_sizing_failure(strike, sizing)
        return skip!(:invalid_quantity)
      end
      log_sizing_success(strike, derivative.lot_size, sizing) if sizing[:lots]

      if USE_SUPER_ORDER
        order = build_super_order_payload(strike, derivative, quantity)
        return skip!(:ltp_unavailable) unless order

        ENV['PLACE_ORDER'] == 'true' ? place_super_order!(order) : dry_run(order)
      else
        order = build_legacy_order_payload(derivative, quantity)
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
      derivative.ltp || begin
        payload = { derivative.exchange_segment => [derivative.security_id.to_i] }
        response = DhanHQ::Models::MarketFeed.ltp(payload)

        # Extract last_price from nested response structure
        data = response[:data] || response['data'] || response
        return nil unless data

        segment_data = data[derivative.exchange_segment] || data[derivative.exchange_segment.to_sym]
        return nil unless segment_data

        security_data = segment_data[derivative.security_id.to_s] || segment_data[derivative.security_id.to_i]
        return nil unless security_data

        security_data[:last_price] || security_data['last_price']
      end
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
    def build_legacy_order_payload(derivative, quantity)
      IndexOrderPayloadBuilder.build_legacy(
        derivative: derivative,
        quantity: quantity,
        signal_type: alert[:signal_type],
        order_type: alert[:order_type]
      )
    end

    def build_super_order_payload(strike, derivative, quantity)
      live = option_ltp(derivative)
      unless live
        log :error, "LTP fetch failed for #{derivative.security_id}"
        return
      end

      rr = rrules_for(live) || rrules_for(strike[:last_price])
      IndexOrderPayloadBuilder.build_super(
        derivative: derivative,
        quantity: quantity,
        signal_type: alert[:signal_type],
        order_type: alert[:order_type],
        entry_price: live.to_f,
        stop_loss: rr[:stop_loss],
        target: rr[:target],
        trailing_jump: rr[:trail_jump]
      )
    end

    def place_order!(params)
      order = DhanHQ::Models::Order.new(params)
      order.save
      order_id = order.order_id || order.id
      log :info, "order placed  → #{order_id}"
      alert.update!(error_message: "orderId #{order_id}")

      notify(<<~MSG.strip, tag: 'ORDER')
        ✅ Order Placed – Alert ##{alert.id}
        • Symbol: #{instrument.symbol_name}
        • Type: #{params[:transaction_type]}
        • Qty: #{params[:quantity]}
        • Order ID: #{order_id}
      MSG
    rescue DhanHQ::OrderError => e
      # Handle market-closed errors specially
      if e.message.include?('Market is Closed')
        log :warn, "Market is closed – skipping order placement: #{e.message}"
        raise "Market is closed: #{e.message}"
      else
        # Re-raise other order errors
        log :error, "Order placement failed: #{e.message}"
        raise
      end
    end

    def place_super_order!(params)
      order = DhanHQ::Models::SuperOrder.create(params)
      order_id = order.order_id || order.id
      log :info, "super-order placed → #{order_id}"
      alert.update!(error_message: "SO #{order_id}")

      notify(<<~MSG.strip, tag: 'SUPER')
        🚀 Super-Order Placed – Alert ##{alert.id}
        • Symbol : #{instrument.symbol_name}
        • Qty    : #{params[:quantity]}
        • Entry  : ₹#{params[:price]}
        • SL     : ₹#{params[:stop_loss_price]}
        • TP     : ₹#{params[:target_price]}
        • Trail  : ₹#{params[:trailing_jump]}
        • SO-ID  : #{order_id}
      MSG
    rescue DhanHQ::OrderError => e
      # Handle market-closed errors specially
      if e.message.include?('Market is Closed')
        log :warn, "Market is closed – skipping super-order placement: #{e.message}"
        raise "Market is closed: #{e.message}"
      else
        # Re-raise other order errors
        log :error, "Super-order placement failed: #{e.message}"
        raise
      end
    end

    # ────────────────────────────────────────────────────────────
    # Latest 5-minute ATR% that Market::AnalysisUpdater wrote.
    # Returns nil if no fresh row (<10 min old) exists.
    # ────────────────────────────────────────────────────────────
    def current_atr_pct
      row = IntradayAnalysis.for_symbol_timeframe(instrument.underlying_symbol, '5m')
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
        • Type: #{params[:transaction_type]}
        • Qty: #{params[:quantity]}
      MSG
    end

    def deployment_policy(balance = available_balance.to_f)
      IndexQuantityCalculator.policy(balance)
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
      false
    end

    # Calculate today's realized loss from positions
    def daily_loss_today
      Rails.cache.fetch("daily_loss:#{Date.current}", expires_in: 1.hour) do
        positions = DhanHQ::Models::Position.all
        positions.sum do |pos|
          pos_hash = pos.is_a?(Hash) ? pos : pos.to_h
          realized_pnl = pos_hash['realizedProfit'] || pos_hash[:realized_profit] || 0
          realized_pnl.to_f.negative? ? realized_pnl.to_f : 0
        end
      end
    end

    # -- Sizing (delegates to IndexQuantityCalculator) ------------------------
    def calculate_quantity(strike, lot_size)
      sizing = quantity_calculator_result(strike, lot_size)
      if sizing[:invalid]
        strike_info = "Strike #{strike[:strike_price]} | Last: #{strike[:last_price]}"
        log :error, "❗ Invalid sizing inputs (lot=#{sizing[:lot_size]}, price=#{sizing[:price]}) for #{instrument.id} (#{strike_info})"
      end
      sizing[:quantity] || 0
    end

    def quantity_calculator_result(strike, lot_size)
      balance = available_balance.to_f
      sl_pct = effective_sl_pct(strike[:last_price].to_f)
      IndexQuantityCalculator.quantity(
        strike: strike,
        lot_size: lot_size,
        balance: balance,
        sl_pct: sl_pct,
        return_details: true
      )
    end

    def log_sizing_failure(strike, sizing)
      strike_info = "Strike #{strike[:strike_price]} | Last: #{strike[:last_price]}"
      if sizing[:invalid]
        log :error, "❗ Invalid sizing inputs (lot=#{sizing[:lot_size]}, price=#{sizing[:price]}) for #{instrument.id} (#{strike_info})"
      elsif sizing[:per_lot_cost] && sizing[:balance] && sizing[:per_lot_cost] > sizing[:balance]
        log_insufficient_margin(strike_info, sizing[:per_lot_cost], sizing[:balance])
      else
        log :warn, "🚫 Sizing → No size fits constraints. alloc_cap=₹#{PriceMath.round_tick(sizing[:alloc_cap])}, " \
                  "risk_cap=₹#{PriceMath.round_tick(sizing[:risk_cap])}, per_lot_cost=₹#{PriceMath.round_tick(sizing[:per_lot_cost])}, " \
                  "per_lot_risk=₹#{PriceMath.round_tick(sizing[:per_lot_risk])}"
      end
    end

    def log_sizing_success(strike, lot_size, sizing)
      lots = sizing[:lots]
      total_cost = lots * sizing[:per_lot_cost]
      total_risk = lots * sizing[:per_lot_risk]
      log :info, "✅ Sizing decided: #{lots} lot(s) (qty ~ #{lots * lot_size}). " \
                 "Alloc cap: ₹#{PriceMath.round_tick(sizing[:alloc_cap])}, Risk cap: ₹#{PriceMath.round_tick(sizing[:risk_cap])}. " \
                 "Per-lot cost: ₹#{PriceMath.round_tick(sizing[:per_lot_cost])}, Per-lot risk: ₹#{PriceMath.round_tick(sizing[:per_lot_risk])}. " \
                 "Total cost: ₹#{PriceMath.round_tick(total_cost)}, Total risk: ₹#{PriceMath.round_tick(total_risk)}. " \
                 "(SL%≈#{(sizing[:sl_pct] * 100).round(1)}%)"
    end

    # -- Positions helpers ----------------------------------------------------
    def open_long_ce_position?
      open_long_position?(ce_security_ids)
    end

    def open_long_pe_position?
      open_long_position?(pe_security_ids)
    end

    def open_long_position?(sec_ids)
      dhan_positions.any? do |p|
        p_hash = p.is_a?(Hash) ? p : p.to_h
        position_type = p_hash['positionType'] || p_hash[:position_type] || p_hash['position_type']
        security_id = p_hash['securityId'] || p_hash[:security_id] || p_hash['security_id']
        position_type == 'LONG' && sec_ids.include?(security_id.to_s)
      end
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
      positions = dhan_positions.select do |p|
        p_hash = p.is_a?(Hash) ? p : p.to_h
        position_type = p_hash['positionType'] || p_hash[:position_type] || p_hash['position_type']
        security_id = p_hash['securityId'] || p_hash[:security_id] || p_hash['security_id']
        position_type == 'LONG' && ids.include?(security_id.to_s)
      end
      return skip!("no #{type.upcase} position to exit") if positions.empty?

      positions.each do |pos|
        pos_hash = pos.is_a?(Hash) ? pos : pos.to_h
        order = DhanHQ::Models::Order.new(
          transaction_type: 'SELL',
          order_type: 'MARKET',
          product_type: 'MARGIN',
          validity: 'DAY',
          security_id: pos_hash['securityId'] || pos_hash[:security_id],
          exchange_segment: pos_hash['exchangeSegment'] || pos_hash[:exchange_segment],
          quantity: pos_hash['quantity'] || pos_hash[:quantity]
        )
        order.save
        log :info,
            "closed #{type.upcase} ⇒ security_id=#{pos_hash['securityId'] || pos_hash[:security_id]}, quantity=#{pos_hash['quantity'] || pos_hash[:quantity]}"
        notify("📤 Exited #{type.upcase} position(s) for Alert ##{alert.id}", tag: 'EXIT')
      end
      alert.update!(status: :processed, error_message: "exited #{type.upcase}")
      false
    end

    # Immediately closes all open opposite-side positions
    def close_opposite!(type)
      ids = type == :ce ? ce_security_ids : pe_security_ids
      positions = dhan_positions.select do |p|
        p_hash = p.is_a?(Hash) ? p : p.to_h
        position_type = p_hash['positionType'] || p_hash[:position_type] || p_hash['position_type']
        security_id = p_hash['securityId'] || p_hash[:security_id] || p_hash['security_id']
        position_type == 'LONG' && ids.include?(security_id.to_s)
      end
      return if positions.empty?

      positions.each do |pos|
        pos_hash = pos.is_a?(Hash) ? pos : pos.to_h
        order = DhanHQ::Models::Order.new(
          transaction_type: 'SELL',
          order_type: 'MARKET',
          product_type: 'MARGIN',
          validity: 'DAY',
          security_id: pos_hash['securityId'] || pos_hash[:security_id],
          exchange_segment: pos_hash['exchangeSegment'] || pos_hash[:exchange_segment],
          quantity: pos_hash['quantity'] || pos_hash[:quantity]
        )
        order.save
        log :info,
            "Flipped & closed #{type.upcase} ⇒ security_id=#{pos_hash['securityId'] || pos_hash[:security_id]}, quantity=#{pos_hash['quantity'] || pos_hash[:quantity]}"
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

  end
end
