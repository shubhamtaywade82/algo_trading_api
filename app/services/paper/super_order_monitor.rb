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
        leg = breached_leg(entry, price)
        next false unless leg

        close(entry, leg)
        true
      end
    end

    private

    attr_reader :account, :exchange

    def entries(security_id)
      account.paper_orders.super_orders.where(security_id: security_id.to_s, status: 'traded')
    end

    # @return [String, nil] "TARGET", "STOP_LOSS", or nil when neither is hit
    def breached_leg(entry, price)
      params = (entry.super_order_params || {}).with_indifferent_access
      target = params[:target_price].to_f
      stop = params[:stop_loss_price].to_f

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
