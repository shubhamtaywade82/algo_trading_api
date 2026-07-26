# frozen_string_literal: true

module Paper
  # The simulated exchange: places orders, fills them against live prices,
  # matches resting orders as ticks arrive, and maintains positions and capital.
  #
  # Reached through {Orders::Gateway} when `PAPER_TRADING=true`, so strategy
  # code is identical between paper and live — only the destination changes.
  #
  # Market data is real (WebSocket cache, then REST); only execution is
  # simulated. That is the whole point: a paper run that used synthetic prices
  # would tell you nothing about a strategy's edge.
  class Exchange < ApplicationService
    class << self
      # @param payload [Hash] the same payload a live placement takes
      # @param source [String, nil] caller identifier for logs
      # @return [Hash] gateway-shaped result
      def place(payload, source: nil)
        new(account: PaperAccount.current).place(payload, source: source)
      end

      # Drives resting orders and marks positions. Called per tick.
      #
      # @param security_id [String]
      # @param exchange_segment [String]
      # @param ltp [Numeric]
      def process_tick(security_id:, exchange_segment:, ltp:)
        new(account: PaperAccount.current)
          .process_tick(security_id: security_id, exchange_segment: exchange_segment, ltp: ltp)
      end

      def cancel(order_id)
        new(account: PaperAccount.current).cancel(order_id)
      end

      def exit_all!
        new(account: PaperAccount.current).exit_all!
      end
    end

    def initialize(account: PaperAccount.current)
      @account = account
      @settings = account.settings
      @engine = MatchingEngine.new(@settings)
      @costs = CostCalculator.new
      @margin = MarginCalculator.new(@settings)
    end

    attr_reader :account

    # @return [Hash] gateway-shaped result
    def place(payload, source: nil)
      params = payload.to_h.symbolize_keys
      errors = validate(params)
      return rejected(params, errors, source: source) if errors.any?

      order = build_order(params)
      margin = @margin.check(account, exchange_segment: order.exchange_segment,
                                      product_type: order.product_type,
                                      quantity: order.quantity,
                                      price: reference_price(order) || order.price.to_f)

      unless margin[:sufficient]
        order.update!(status: 'rejected',
                      rejection_reason: { code: 'MARGIN', required: margin[:required], available: margin[:available] })
        return result_for(order, message: 'Insufficient paper margin')
      end

      @margin.block!(account, margin[:required])
      order.update!(metadata: order.metadata.merge('blocked_margin' => margin[:required]))

      attempt_fill(order)
      result_for(order)
    rescue StandardError => e
      Rails.logger.error("[Paper::Exchange] place failed: #{e.class} - #{e.message}")
      { dry_run: false, paper: true, error: true, message: e.message, payload: payload }
    end

    # Fills resting orders whose trigger the tick crosses, marks open
    # positions, and checks super-order target/stop legs.
    def process_tick(security_id:, exchange_segment:, ltp:)
      price = ltp.to_f
      return if price <= 0

      mark_positions(security_id, price)
      fill_resting_orders(security_id, exchange_segment, price)
      super_monitor.check(security_id, price)
    rescue StandardError => e
      Rails.logger.error("[Paper::Exchange] tick processing failed for #{security_id}: #{e.message}")
    end

    def cancel(order_id)
      order = account.paper_orders.find_by(id: order_id)
      return { paper: true, error: true, message: 'Order not found' } unless order
      return { paper: true, error: true, message: "Cannot cancel a #{order.status} order" } unless order.open?

      release_margin(order)
      order.update!(status: 'cancelled', cancelled_at: Time.current)
      result_for(order)
    end

    # Closes every open position at market.
    def exit_all!
      exited = account.paper_positions.open_positions.map do |position|
        # Braces matter: `place` takes a positional payload, so bare keywords
        # would arrive as kwargs and raise "given 0, expected 1".
        place({
                security_id: position.security_id,
                exchange_segment: position.exchange_segment,
                transaction_type: position.net_qty.positive? ? 'SELL' : 'BUY',
                quantity: position.net_qty.abs,
                order_type: 'MARKET',
                product_type: position.product_type
              })
      end
      { paper: true, exited: exited.size, results: exited }
    end

    private

    attr_reader :settings, :engine, :costs, :margin

    # ── Validation ──────────────────────────────────────────────────────

    def validate(params)
      errors = []
      errors << 'Market is closed' if enforce_hours? && !market_open?
      errors << 'Quantity must be positive' unless params[:quantity].to_i.positive?
      errors << 'LIMIT orders require a positive price' if limit_without_price?(params)
      errors.concat(lot_size_errors(params))
      errors
    end

    def limit_without_price?(params)
      params[:order_type].to_s.casecmp('LIMIT').zero? && params[:price].to_f <= 0
    end

    def lot_size_errors(params)
      return [] unless params[:exchange_segment].to_s.include?('FNO')

      instrument = Instrument.find_by(security_id: params[:security_id].to_s)
      lot = instrument&.lot_size.to_i
      return [] unless lot.positive?
      return [] if (params[:quantity].to_i % lot).zero?

      ["Quantity must be a multiple of lot size #{lot}"]
    rescue StandardError
      []
    end

    def enforce_hours?
      settings['market_hours_enforced'].to_s == 'true' || settings['market_hours_enforced'] == true
    end

    def market_open?
      return MarketCalendar.market_open? if defined?(MarketCalendar) && MarketCalendar.respond_to?(:market_open?)

      now = Time.current.in_time_zone('Asia/Kolkata')
      now.on_weekday? && now.between?(now.change(hour: 9, min: 15), now.change(hour: 15, min: 30))
    end

    # ── Placement ───────────────────────────────────────────────────────

    def build_order(params)
      account.paper_orders.create!(
        correlation_id: params[:correlation_id] || "paper-#{SecureRandom.hex(6)}",
        status: 'initiated',
        transaction_type: params[:transaction_type].to_s.upcase,
        exchange_segment: params[:exchange_segment].to_s,
        product_type: (params[:product_type].presence || 'INTRADAY').to_s.upcase,
        order_type: (params[:order_type].presence || 'MARKET').to_s.upcase,
        validity: (params[:validity].presence || 'DAY').to_s.upcase,
        security_id: params[:security_id].to_s,
        trading_symbol: params[:trading_symbol],
        quantity: params[:quantity].to_i,
        remaining_quantity: params[:quantity].to_i,
        price: params[:price],
        trigger_price: params[:trigger_price],
        order_category: params[:super_order_params].present? ? 'super' : (params[:order_category] || 'regular'),
        super_order_params: params[:super_order_params],
        metadata: params[:metadata] || {},
        placed_at: Time.current
      )
    end

    # Tries to fill now; anything unfilled rests.
    def attempt_fill(order)
      price = reference_price(order)

      # A stop has not been elected until price trades through its trigger.
      # Without this it would fill the moment it was placed, which would make
      # every stop-entry strategy look like a market order.
      return order.update!(status: 'pending') if stop_order?(order) && !triggered?(order, price.to_f)

      fill = engine.fill_price(
        order_type: order.order_type, limit_price: order.price, market_price: price,
        transaction_type: order.transaction_type, quantity: order.unfilled_qty,
        security_id: order.security_id, exchange_segment: order.exchange_segment
      )

      return order.update!(status: 'pending') if fill.nil?

      qty = engine.fill_quantity(order.unfilled_qty, security_id: order.security_id)
      apply_fill(order, qty, fill)
    end

    def apply_fill(order, qty, price)
      charge = costs.calculate(
        transaction_type: order.transaction_type, exchange_segment: order.exchange_segment,
        product_type: order.product_type, quantity: qty, price: price
      )

      record_fill(order, qty, price, charge)
      settle_cash(order, qty, price, charge)
      update_position(order, qty, price)
      release_margin(order) if order.reload.status == 'traded'
      order
    end

    def record_fill(order, qty, price, charge)
      filled = order.filled_qty.to_i + qty
      avg = weighted_avg(order, qty, price)
      slippage = order.price.to_f.positive? ? (price - order.price.to_f).abs : 0

      order.update!(
        filled_qty: filled,
        remaining_quantity: order.quantity.to_i - filled,
        average_traded_price: avg,
        slippage_applied: slippage,
        charges: order.charges.to_f + charge[:total],
        status: filled >= order.quantity.to_i ? 'traded' : 'part_traded',
        filled_at: filled >= order.quantity.to_i ? Time.current : order.filled_at,
        fill_details: order.fill_details + [{
          qty: qty, price: price, at: Time.current.iso8601, slippage: slippage, charges: charge
        }]
      )
    end

    def weighted_avg(order, qty, price)
      prior = order.filled_qty.to_i
      return price if prior.zero?

      ((order.average_traded_price.to_f * prior) + (price * qty)) / (prior + qty)
    end

    # Cash moves by the traded value; charges always debit.
    def settle_cash(order, qty, price, charge)
      value = qty * price
      delta = order.buy? ? -value : value

      account.update!(
        available_balance: account.available_balance.to_f + delta - charge[:total],
        total_charges: account.total_charges.to_f + charge[:total]
      )
    end

    # ── Positions ───────────────────────────────────────────────────────

    def update_position(order, qty, price)
      position = account.paper_positions.find_or_initialize_by(
        security_id: order.security_id, product_type: order.product_type
      )
      position.exchange_segment = order.exchange_segment
      position.trading_symbol ||= order.trading_symbol

      net_before = position.net_qty.to_i
      entry_before = position.entry_price
      apply_leg(position, order, qty, price)
      position.recalculate_net!
      realized = realize_reduction(position, order, qty, price, net_before, entry_before)
      position.save!

      account.update!(realized_pnl: account.realized_pnl.to_f + realized) unless realized.zero?
    end

    # Realises P&L only on the quantity this fill actually closed.
    #
    # A fill realises nothing when it opens or extends a position; it realises
    # against the prior average only for the portion that offsets an existing
    # net quantity. Anything beyond that flips the position and becomes the new
    # entry, so it must not be counted.
    #
    # @param net_before [Integer] net quantity before this fill
    # @param entry_before [Float] weighted entry before this fill
    # @return [Float] realised P&L, added to the position and the account
    def realize_reduction(position, order, qty, price, net_before, entry_before)
      return 0.0 if net_before.zero?

      reducing = order.buy? ? net_before.negative? : net_before.positive?
      return 0.0 unless reducing

      closed = [qty, net_before.abs].min
      # Long closed by a sell earns (exit - entry); short closed by a buy earns
      # (entry - exit).
      pnl = net_before.positive? ? (price - entry_before) * closed : (entry_before - price) * closed
      position.realized_profit = position.realized_profit.to_f + pnl
      pnl
    end

    def apply_leg(position, order, qty, price)
      if order.buy?
        new_qty = position.buy_qty.to_i + qty
        position.buy_avg = ((position.buy_avg.to_f * position.buy_qty.to_i) + (price * qty)) / new_qty
        position.buy_qty = new_qty
      else
        new_qty = position.sell_qty.to_i + qty
        position.sell_avg = ((position.sell_avg.to_f * position.sell_qty.to_i) + (price * qty)) / new_qty
        position.sell_qty = new_qty
      end
    end

    def mark_positions(security_id, price)
      account.paper_positions.where(security_id: security_id.to_s).open_positions.find_each do |position|
        position.mark_to_market!(price)
      end
    end

    # ── Resting orders ──────────────────────────────────────────────────

    def fill_resting_orders(security_id, exchange_segment, price)
      account.paper_orders.resting.where(security_id: security_id.to_s).find_each do |order|
        next unless triggered?(order, price)

        fill = engine.fill_price(
          order_type: order.order_type, limit_price: order.price, market_price: price,
          transaction_type: order.transaction_type, quantity: order.unfilled_qty,
          security_id: security_id, exchange_segment: exchange_segment
        )
        next if fill.nil?

        apply_fill(order, engine.fill_quantity(order.unfilled_qty, security_id: security_id), fill)
      end
    end

    def stop_order?(order)
      %w[STOP_LOSS STOP_LOSS_MARKET].include?(order.order_type)
    end

    # Whether the tick crosses the order's trigger.
    def triggered?(order, price)
      case order.order_type
      when 'MARKET' then true
      when 'LIMIT' then order.buy? ? price <= order.price.to_f : price >= order.price.to_f
      when 'STOP_LOSS', 'STOP_LOSS_MARKET'
        trigger = order.trigger_price.to_f
        return false unless trigger.positive?

        order.buy? ? price >= trigger : price <= trigger
      else false
      end
    end

    # ── Helpers ─────────────────────────────────────────────────────────

    def super_monitor
      @super_monitor ||= SuperOrderMonitor.new(account: account, exchange: self)
    end

    def release_margin(order)
      blocked = order.metadata['blocked_margin'].to_f
      return unless blocked.positive?

      @margin.release!(account, blocked)
      order.update!(metadata: order.metadata.merge('blocked_margin' => 0))
    end

    # Real market data: WebSocket cache first, REST second.
    def reference_price(order)
      Live::TickCache.ltp(order.exchange_segment, order.security_id) ||
        rest_price(order.security_id) ||
        order.price&.to_f
    end

    def rest_price(security_id)
      Instrument.find_by(security_id: security_id.to_s)&.ltp&.to_f
    rescue StandardError
      nil
    end

    def rejected(params, errors, source: nil)
      Rails.logger.info("[Paper::Exchange] rejected: #{errors.join('; ')}#{source ? " (source=#{source})" : ''}")
      { dry_run: false, paper: true, error: true, blocked: true, message: errors.join('; '), payload: params }
    end

    def result_for(order, message: nil)
      {
        dry_run: false,
        paper: true,
        order_id: order.id,
        correlation_id: order.correlation_id,
        order_status: order.status.upcase,
        filled_qty: order.filled_qty,
        average_traded_price: order.average_traded_price&.to_f,
        charges: order.charges.to_f,
        error: order.status == 'rejected',
        message: message || order.rejection_reason&.dig('code'),
        raw: order
      }
    end
  end
end
