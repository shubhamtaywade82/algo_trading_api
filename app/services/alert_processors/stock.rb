# frozen_string_literal: true

module AlertProcessors
  # Refactored STOCK processor – mirrors the flow & logging style of the
  # Index processor (metadata logging, skip! helper, tagged logs, etc.)
  # ----------------------------------------------------------------------------
  class Stock < Base
    include Strategies

    STRATEGY = {
      'intraday' => Strategies::Intraday,
      'swing' => Strategies::Swing,
      'long_term' => Strategies::LongTerm
    }.freeze

    PRODUCT = {
      'intraday' => 'INTRADAY',
      'swing' => 'CNC',
      'long_term' => 'CNC'
    }.freeze

    LONG_ONLY      = %w[swing long_term].freeze
    LONG_SIGNALS   = %w[long_entry long_exit].freeze
    SHORT_SIGNALS  = %w[short_entry short_exit].freeze

    # sizing constants --------------------------------------------------------
    RISK_PER_TRADE     = 0.02  # 2 % of equity
    FUNDS_UTILIZATION  = 0.30  # 30 % of free cash per trade

    EDIS_POLL_INTERVAL = 5.seconds
    EDIS_TIMEOUT       = 45.seconds

    # ──────────────────────────────────────────────────────────────────
    # Capital-aware deployment policy
    # ──────────────────────────────────────────────────────────────────
    CAPITAL_BANDS = [
      { upto: 75_000, alloc_pct: 0.30, risk_per_trade_pct: 0.050, daily_max_loss_pct: 0.050 }, # small a/c (≈ ₹50k)
      { upto: 150_000,  alloc_pct: 0.25, risk_per_trade_pct: 0.035, daily_max_loss_pct: 0.060 }, # ≈ ₹1L
      { upto: 300_000,  alloc_pct: 0.20, risk_per_trade_pct: 0.030, daily_max_loss_pct: 0.060 }, # ≈ ₹2–3L
      { upto: Float::INFINITY, alloc_pct: 0.20, risk_per_trade_pct: 0.025, daily_max_loss_pct: 0.050 }
    ].freeze

    # ------------------------------------------------------------------------
    #  Entry‑point (called from controller / worker)
    # ------------------------------------------------------------------------
    def call
      with_tag do
        return skip! unless signal_guard?
        return skip! unless daily_loss_guard_ok?

        order = build_order_payload
        ENV['PLACE_ORDER'] == 'true' ? place_order!(order) : dry_run(order)

        alert.update!(status: :processed)
      end
    rescue StandardError => e
      # Handle market-closed errors by skipping instead of failing
      if e.message.include?('Market is closed')
        logger.warn("[Stock ##{alert.id}] Market is closed – skipping alert: #{e.message}")
        skip!(:market_closed)
      # Handle LTP fetch failures gracefully
      elsif e.message.include?('Failed to fetch LTP')
        logger.warn("[Stock ##{alert.id}] LTP unavailable – skipping alert: #{e.message}")
        skip!(:ltp_unavailable)
      else
        alert.update!(status: :failed, error_message: e.message)
        logger.error("[Stock ##{alert.id}] #{e.class} – #{e.message}\n" \
                     "#{e.backtrace.first(6).join("\n")}")
      end
    end

    # ------------------------------------------------------------------------
    #  Strategy descriptor
    # ------------------------------------------------------------------------
    def strat
      @strat ||= STRATEGY.fetch(alert[:strategy_type]).new(self)
    end

    # ------------------------------------------------------------------------
    #  Guards / validation
    # ------------------------------------------------------------------------
    def signal_guard?
      return skip!(:short_not_allowed) if LONG_ONLY.include?(alert[:strategy_type]) && SHORT_SIGNALS.include?(alert[:signal_type])

      case alert[:signal_type]
      when 'long_entry'  then return skip!(:already_long)   if current_qty.positive?
      when 'long_exit'   then return skip!(:no_long)        if current_qty.zero?
      when 'short_entry' then return skip!(:already_short)  if current_qty.negative?
      when 'short_exit'  then return skip!(:no_short)       if current_qty.zero?
      end
      true
    end

    # --------------------------------------------------------------------
    #  Order building – honours DhanHQ field-matrix
    # --------------------------------------------------------------------
    def build_order_payload
      order_type  = alert[:order_type].to_s.upcase
      txn_side    = side_for(alert[:signal_type])

      payload = {
        transaction_type: txn_side,
        order_type: order_type, # MARKET / LIMIT / SL / SLM
        product_type: PRODUCT.fetch(alert[:strategy_type]),
        validity: 'DAY',
        exchange_segment: instrument.exchange_segment,
        security_id: instrument.security_id,
        quantity: calculate_quantity!
      }

      # Set price based on order type
      if order_type == 'STOP_LOSS_MARKET'
        trigger = derived_stop_price(txn_side)
        payload[:trigger_price] = PriceMath.round_tick(trigger)
        payload[:price] = 0 # Market order
      elsif order_type == 'STOP_LOSS'
        trigger = derived_stop_price(txn_side)
        payload[:trigger_price] = PriceMath.round_tick(trigger)
        payload[:price] = PriceMath.round_tick(ltp)
      elsif order_type == 'MARKET'
        # MARKET orders don't need a price
      else
        payload[:price] = PriceMath.round_tick(ltp)
      end

      payload
    end

    def side_for(sig)
      case sig
      when 'long_entry',  'short_exit'  then 'BUY'
      when 'long_exit',   'short_entry' then 'SELL'
      else raise "Unknown signal_type #{sig}"
      end
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

    # Daily loss guard - prevents new entries when daily loss exceeds band limit
    def daily_loss_guard_ok?
      policy = deployment_policy
      max_loss = available_balance.to_f * policy[:daily_max_loss_pct]
      loss_today = daily_loss_today
      return true if loss_today.to_f.abs < max_loss.abs

      logger.warn("[Stock ##{alert.id}] ⛔️ Daily loss guard hit: #{PriceMath.round_tick(loss_today)} >= max #{PriceMath.round_tick(max_loss)}")
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

    # ------------------------------------------------------------------------
    #  Sizing helpers
    # ------------------------------------------------------------------------
    def calculate_quantity!
      return current_qty.abs if closing_trade?

      balance = available_balance.to_f
      policy = deployment_policy(balance)

      # Capital-aware sizing for stocks
      alloc_cap = balance * policy[:alloc_pct]
      risk_cap = balance * policy[:risk_per_trade_pct]

      # Stock-specific risk calculation (using stop loss %)
      sl_pct = 0.04 # 4% stop loss for stocks (from risk manager)
      per_share_risk = ltp * sl_pct

      # Calculate quantities based on constraints
      alloc_qty = (alloc_cap / ltp).floor
      risk_qty = per_share_risk.positive? ? (risk_cap / per_share_risk).floor : 0
      afford_qty = (balance / ltp).floor

      # Take minimum of all constraints
      qty = [alloc_qty, risk_qty, afford_qty].min
      qty = [qty, min_lot_by_price].max

      if qty.zero?
        logger.warn("[Stock ##{alert.id}] 🚫 Sizing failed: alloc_cap=₹#{PriceMath.round_tick(alloc_cap)}, " \
                    "risk_cap=₹#{PriceMath.round_tick(risk_cap)}, per_share_risk=₹#{PriceMath.round_tick(per_share_risk)}")
        raise 'buying‑power insufficient for minimum lot'
      end

      total_cost = qty * ltp
      total_risk = qty * per_share_risk

      logger.info("[Stock ##{alert.id}] ✅ Sizing decided: #{qty} shares. " \
                  "Alloc cap: ₹#{PriceMath.round_tick(alloc_cap)}, Risk cap: ₹#{PriceMath.round_tick(risk_cap)}. " \
                  "Per-share cost: ₹#{PriceMath.round_tick(ltp)}, Per-share risk: ₹#{PriceMath.round_tick(per_share_risk)}. " \
                  "Total cost: ₹#{PriceMath.round_tick(total_cost)}, Total risk: ₹#{PriceMath.round_tick(total_risk)}. " \
                  "(SL%≈#{(sl_pct * 100).round(1)}%)")

      qty
    end

    def closing_trade?
      (alert[:signal_type] == 'long_exit' && current_qty.positive?) ||
        (alert[:signal_type] == 'short_exit' && current_qty.negative?)
    end

    # min‑lot table (mirrors Dhan UI) ----------------------------------------
    def min_lot_by_price
      base = case ltp
             when 0..50       then 250
             when 51..200     then 50
             when 201..500    then 25
             when 501..1_000  then 5
             else 1
             end
      PRODUCT.fetch(alert[:strategy_type]) == 'INTRADAY' ? base * 2 : base
    end

    # ------------------------------------------------------------------------
    #  Execution helpers
    # ------------------------------------------------------------------------
    def place_order!(payload)
      order = DhanHQ::Models::Order.new(payload)
      order.save
      order_id = order.order_id || order.id
      ensure_edis!(payload[:quantity]) if cnc_sell?(payload)
      alert.update!(metadata: { placed_order: { order_id: order_id } })
      logger.info("[Stock ##{alert.id}] ✅ placed #{order_id}")
    rescue DhanHQ::OrderError => e
      # Handle market-closed errors specially
      if e.message.include?('Market is Closed')
        logger.warn("[Stock ##{alert.id}] Market is closed – skipping order placement: #{e.message}")
        raise "Market is closed: #{e.message}"
      else
        # Re-raise other order errors
        logger.error("[Stock ##{alert.id}] Order placement failed: #{e.message}")
        raise
      end
    end

    def dry_run(payload)
      alert.update!(status: :skipped,
                    error_message: 'PLACE_ORDER disabled',
                    metadata: { simulated_order: payload })
      logger.info("[Stock ##{alert.id}] 💡 dry‑run #{payload}")
    end

    def cnc_sell?(payload)
      payload[:product_type] == 'CNC' &&
        payload[:transaction_type] == 'SELL'
    end

    # eDIS (idempotent)
    def ensure_edis!(qty)
      info = Dhanhq::API::EDIS.status(isin: instrument.isin)
      return if info['status'] == 'SUCCESS' && info['aprvdQty'].to_i >= qty

      Dhanhq::API::EDIS.mark(
        isin: instrument.isin,
        qty: qty,
        exchange: instrument.exchange.upcase,
        segment: 'EQ',
        bulk: true
      )

      start = Time.current
      loop do
        sleep EDIS_POLL_INTERVAL
        info = Dhanhq::API::EDIS.status(isin: instrument.isin)
        break if info['status'] == 'SUCCESS' && info['aprvdQty'].to_i >= qty
        raise 'eDIS approval timed‑out' if Time.current - start > EDIS_TIMEOUT
      end
    end

    # ------------------------------------------------------------------------
    #  Helpers delegated to Base / external
    # ------------------------------------------------------------------------
    def current_qty
      pos = dhan_positions.find { |p| p['securityId'].to_s == instrument.security_id.to_s }
      pos&.dig('netQty').to_i
    end
    alias fetch_current_net_quantity current_qty

    def leverage_factor
      lev = instrument.mis_detail&.mis_leverage.to_i
      lev.positive? ? lev : 1.0
    end

    # ------------------------------------------------------------------------
    #  Logging helpers
    # ------------------------------------------------------------------------
    def with_tag(&)
      logger.tagged("Stock ##{alert.id}", &)
    end

    def skip!(reason = nil)
      reason ? alert.update!(status: :skipped, error_message: reason.to_s) : alert.update!(status: :skipped)
      logger.info("[Stock ##{alert.id}] skip – #{reason}")
      false
    end

    def logger = Rails.logger

    def derived_stop_price(txn_side)
      base_trigger = stop_price_from_metadata
      return base_trigger if base_trigger.positive?

      margin = PriceMath.round_tick(ltp * 0.05)
      case txn_side
      when 'BUY'  then (ltp - margin)   # long stop 5 % below entry
      when 'SELL' then (ltp + margin)   # short stop 5 % above entry
      else
        raise "Unexpected txn_side #{txn_side}"
      end
    end
    private :derived_stop_price

    # Reads a numeric :stop_price inside alert.metadata (if present)
    # Returns 0.0 when the key is missing or not numeric.
    def stop_price_from_metadata
      m = alert.metadata || {}
      price = m['stop_price'] || m[:stop_price]
      price.to_f
    rescue StandardError
      0.0
    end
  end
end
