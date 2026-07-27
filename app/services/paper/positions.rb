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

      # The paper book rendered in the broker's position shape, so guards,
      # dedupe and exit logic can read it through
      # {AlertProcessors::Base#dhan_positions} without knowing which book they
      # are on.
      #
      # Both spellings of every key are present. Callers across this app reach
      # for camelCase (`securityId`, straight off the Dhan API) and snake_case
      # interchangeably, and a hash answering only one of them would read as a
      # flat position — which is exactly how a paper run silently places the
      # same entry twice.
      #
      # Closed positions are included, as Dhan includes them: realised P&L
      # lives on the row that closed, so the daily-loss guard would always see
      # zero without them.
      #
      # @param since [Time] day boundary; Dhan's positions API is day-scoped
      # @return [Array<ActiveSupport::HashWithIndifferentAccess>]
      def dhan_shaped(since: Time.current.in_time_zone('Asia/Kolkata').beginning_of_day)
        account.paper_positions.where(updated_at: since..).map { |position| dhan_attributes(position) }
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

      # `realizedProfit` is the row's lifetime realised P&L, not strictly
      # today's: the paper book has no end-of-day rollover, so a position
      # reduced at a loss on more than one day over-reports the current day.
      # Intraday product types close out the same session, so this only bites
      # a CNC position scaled out across sessions.
      def dhan_attributes(position)
        attrs = {
          security_id: position.security_id,
          exchange_segment: position.exchange_segment,
          product_type: position.product_type,
          trading_symbol: position.trading_symbol,
          position_type: position.position_type,
          net_qty: position.net_qty.to_i,
          buy_qty: position.buy_qty.to_i,
          sell_qty: position.sell_qty.to_i,
          buy_avg: position.buy_avg.to_f,
          sell_avg: position.sell_avg.to_f,
          realized_profit: position.realized_profit.to_f,
          unrealized_profit: position.unrealized_profit.to_f,
          ltp: position.ltp.to_f
        }

        attrs.merge(attrs.transform_keys { |key| key.to_s.camelize(:lower) }).with_indifferent_access
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
