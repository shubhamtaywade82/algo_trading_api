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
      # Day scoping is the rollover's job, not a timestamp filter here. After
      # {Paper::DayRollover} has run, every surviving row is either still open —
      # a carry-forward position the broker would also show today — or was
      # closed during the current session. Rolling from this read path is what
      # makes that true even on a day the book has not traded yet.
      #
      # @return [Array<ActiveSupport::HashWithIndifferentAccess>]
      def dhan_shaped
        acct = account
        DayRollover.ensure!(account: acct)

        positions = acct.paper_positions.to_a
        expiries = derivative_expiries(positions)
        positions.map { |position| dhan_attributes(position, expiry: expiries[position.security_id]) }
      end

      # What the book is carrying as delivery, in the broker's holdings shape.
      #
      # A CNC buy sits in the position book on the day it trades and moves to
      # holdings from T+1, so swing and long-term exit logic has to look in
      # both places or it stops finding the position it is meant to close.
      #
      # @return [Array<ActiveSupport::HashWithIndifferentAccess>]
      def dhan_holdings
        account.paper_positions.open_positions.where(product_type: 'CNC').map do |position|
          holding_attributes(position)
        end
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

      # `costPrice` and `drvExpiryDate` are here because the exit stack reads
      # them: Orders::Analyzer prices P&L off `costPrice`, and RiskManager
      # treats expiry day specially. A paper position missing them analyses as
      # worthless and gets skipped.
      def dhan_attributes(position, expiry: nil)
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
          cost_price: position.entry_price,
          realized_profit: position.realized_profit.to_f,
          unrealized_profit: position.unrealized_profit.to_f,
          drv_expiry_date: expiry,
          ltp: position.ltp.to_f
        }

        with_both_spellings(attrs)
      end

      def holding_attributes(position)
        qty = position.net_qty.to_i.abs

        with_both_spellings(
          security_id: position.security_id,
          trading_symbol: position.trading_symbol,
          exchange: position.exchange_segment.to_s.split('_').first,
          total_qty: qty,
          available_qty: qty,
          dp_qty: qty,
          t1_qty: 0,
          avg_cost_price: position.entry_price
        )
      end

      # Callers reach for camelCase and snake_case interchangeably, so answer
      # to both rather than betting on which one a given caller learned.
      def with_both_spellings(attrs)
        attrs.merge(attrs.transform_keys { |key| key.to_s.camelize(:lower) }).with_indifferent_access
      end

      # One query for the whole set: the exit stack asks per position, and a
      # lookup each would be a query per row.
      def derivative_expiries(positions)
        return {} if positions.empty?

        Derivative.where(security_id: positions.map(&:security_id))
          .pluck(:security_id, :expiry_date).to_h
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
