# frozen_string_literal: true

module Paper
  # Simulates the target and stop legs of a super/bracket order.
  #
  # A real super order is managed by the broker: once the entry fills, the
  # exchange holds a target and a stop-loss leg, and whichever trades first
  # cancels the other. Here the tick stream plays that role — a price through
  # either level closes the position at market.
  #
  # Extracted from {Paper::Exchange} because it is a distinct concern with its
  # own lifecycle: the exchange fills orders, this decides when a filled entry
  # should be closed.
  class SuperOrderMonitor
    # @param account [PaperAccount]
    # @param exchange [Paper::Exchange] used to place the closing order
    def initialize(account:, exchange:)
      @account = account
      @exchange = exchange
    end

    # Closes any super-order entry whose target or stop the tick crosses.
    #
    # @param security_id [String]
    # @param price [Float] current LTP
    # @return [Integer] number of entries closed
    def check(security_id, price)
      entries(security_id).count do |entry|
        trail!(entry, price)
        leg = breached_leg(entry, price)
        next false unless leg

        close(entry, leg)
        true
      end
    end

    private

    attr_reader :account, :exchange

    # Partly-filled entries are watched too: a super order that filled half its
    # quantity still has a live position, and leaving it unwatched left it with
    # no stop at all.
    def entries(security_id)
      account.paper_orders.super_orders.where(security_id: security_id.to_s, status: %w[traded part_traded])
    end

    # Ratchets the stop toward price in whole `trailing_jump` steps, the way a
    # Dhan super order does: it moves only in the position's favour, and only
    # once price has travelled a full jump from entry.
    #
    # Without this the leg was recorded and then ignored, so every trailing
    # strategy tested as a fixed stop — flattering anything that gives profit
    # back and penalising nothing.
    def trail!(entry, price)
      params = leg_params(entry)
      jump = params[:trailing_jump].to_f
      base = params[:stop_loss_price].to_f
      entry_price = entry.average_traded_price.to_f
      return unless jump.positive? && base.positive? && entry_price.positive?

      steps = ((entry.buy? ? price - entry_price : entry_price - price) / jump).floor
      return if steps < 1

      trailed = entry.buy? ? base + (steps * jump) : base - (steps * jump)
      return unless improves?(entry, trailed, current_stop(entry, base))

      entry.update!(metadata: entry.metadata.merge('trailed_stop' => trailed))
      Rails.logger.info("[Paper::SuperOrderMonitor] entry #{entry.id} stop trailed to #{trailed.round(2)}")
    end

    def improves?(entry, trailed, current)
      entry.buy? ? trailed > current : trailed < current
    end

    # The trailed stop once it has moved, otherwise the one placed with the
    # order.
    def current_stop(entry, base)
      entry.metadata['trailed_stop'].presence&.to_f || base
    end

    def leg_params(entry)
      (entry.super_order_params || {}).with_indifferent_access
    end

    # @return [String, nil] "TARGET", "STOP_LOSS", or nil when neither is hit
    def breached_leg(entry, price)
      params = leg_params(entry)
      target = params[:target_price].to_f
      stop = current_stop(entry, params[:stop_loss_price].to_f)

      return 'TARGET' if target.positive? && (entry.buy? ? price >= target : price <= target)
      return 'STOP_LOSS' if stop.positive? && (entry.buy? ? price <= stop : price >= stop)

      nil
    end

    def close(entry, leg)
      exchange.place({
                       security_id: entry.security_id,
                       exchange_segment: entry.exchange_segment,
                       transaction_type: entry.opposite_side,
                       quantity: entry.filled_qty,
                       order_type: 'MARKET',
                       product_type: entry.product_type,
                       metadata: { 'super_order_leg' => leg, 'parent_order_id' => entry.id }
                     })
      entry.update!(status: 'closed', metadata: entry.metadata.merge('exit_leg' => leg))
      Rails.logger.info("[Paper::SuperOrderMonitor] entry #{entry.id} closed on #{leg}")
    end
  end
end
