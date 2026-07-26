# frozen_string_literal: true

module Paper
  # Read model over the simulated book.
  #
  # Positions are now maintained incrementally by {Paper::Exchange} as fills
  # arrive, rather than being re-derived from order rows on every read. That
  # matters because margin is blocked and released against them and because
  # marks have to survive a restart.
  class Positions < ApplicationService
    class << self
      # @return [Array<Hash>] positions with a non-zero net quantity
      def open
        account.paper_positions.open_positions.map { |position| serialize(position) }
      end

      # @return [Array<Hash>] every position, including flat ones
      def all
        account.paper_positions.map { |position| serialize(position) }
      end

      # @return [Hash] capital, P&L and charge totals for the book
      def summary
        acct = account
        {
          initial_capital: acct.initial_capital.to_f,
          available_balance: acct.available_balance.to_f,
          blocked_margin: acct.blocked_margin.to_f,
          open_positions: acct.paper_positions.open_positions.count,
          realized_pnl: acct.realized_pnl.to_f.round(2),
          unrealized_pnl: acct.unrealized_pnl.round(2),
          charges: acct.total_charges.to_f.round(2),
          net_pnl: (acct.realized_pnl.to_f + acct.unrealized_pnl - acct.total_charges.to_f).round(2),
          current_capital: acct.current_capital.round(2)
        }
      end

      # @return [Array<Hash>] orders still working
      def open_orders
        account.paper_orders.open_orders.map do |order|
          {
            id: order.id, security_id: order.security_id, side: order.transaction_type,
            order_type: order.order_type, quantity: order.quantity, filled_qty: order.filled_qty,
            price: order.price&.to_f, trigger_price: order.trigger_price&.to_f, status: order.status
          }
        end
      end

      # Returns the book to its starting capital.
      delegate :reset!, to: :account

      private

      def account
        PaperAccount.current
      end

      def serialize(position)
        {
          exchange_segment: position.exchange_segment,
          security_id: position.security_id,
          trading_symbol: position.trading_symbol,
          product_type: position.product_type,
          position_type: position.position_type,
          net_qty: position.net_qty,
          buy_qty: position.buy_qty,
          sell_qty: position.sell_qty,
          buy_avg: position.buy_avg.to_f.round(2),
          sell_avg: position.sell_avg.to_f.round(2),
          ltp: position.ltp.to_f.round(2),
          realized_pnl: position.realized_profit.to_f.round(2),
          unrealized_pnl: position.unrealized_profit.to_f.round(2)
        }
      end
    end
  end
end
