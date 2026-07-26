# frozen_string_literal: true

module Paper
  # Reconstructs net positions and P&L from simulated fills.
  #
  # Paper fills are stored as ordinary `Order` rows with a `PAPER-` prefixed
  # id, so positions are derived rather than tracked: net quantity and the
  # weighted-average entry come from aggregating those rows. That keeps paper
  # state in one place and means a restart loses nothing.
  #
  # Unrealised P&L marks against the live feed via {Live::TickCache}, falling
  # back to the cross-process cache, so a paper book reprices exactly as a live
  # one would. Charges are the real Dhan schedule via {Charges::Calculator} —
  # a paper P&L that ignored brokerage and STT would flatter every strategy.
  class Positions < ApplicationService
    PAPER_ID_PREFIX = 'PAPER-'

    class << self
      # @return [Array<Hash>] one entry per instrument with a non-zero net qty
      def open
        all.reject { |position| position[:net_qty].zero? }
      end

      # @return [Array<Hash>] every instrument touched, including flat ones
      def all
        paper_fills.group_by { |order| [order.exchange_segment, order.security_id] }
          .map { |(segment, security_id), fills| build_position(segment, security_id, fills) }
      end

      # @return [Hash] realised, unrealised and net totals across the book
      def summary
        positions = all
        realised = positions.sum { |p| p[:realized_pnl] }
        unrealised = positions.sum { |p| p[:unrealized_pnl] }
        charges = positions.sum { |p| p[:charges] }

        {
          open_positions: positions.count { |p| !p[:net_qty].zero? },
          realized_pnl: realised.round(2),
          unrealized_pnl: unrealised.round(2),
          charges: charges.round(2),
          net_pnl: (realised + unrealised - charges).round(2)
        }
      end

      # Clears the simulated book. Paper-only by construction — the scope
      # cannot match a live order id.
      def reset!
        paper_fills.delete_all
      end

      private

      def paper_fills
        Order.where(order_status: 'TRADED').where('dhan_order_id LIKE ?', "#{PAPER_ID_PREFIX}%")
      end

      def build_position(segment, security_id, fills)
        # Order#transaction_type is an enum, so it reads back as the key
        # ("buy"), never the DB value ("BUY"). Use the enum predicates rather
        # than comparing strings.
        buys = fills.select(&:transaction_type_buy?)
        sells = fills.select(&:transaction_type_sell?)

        buy_qty = buys.sum { |f| f.filled_qty.to_i }
        sell_qty = sells.sum { |f| f.filled_qty.to_i }
        net_qty = buy_qty - sell_qty

        buy_avg = weighted_average(buys)
        sell_avg = weighted_average(sells)
        ltp = mark_price(segment, security_id) || buy_avg

        # Realised on the matched quantity only; the open leg is unrealised.
        matched = [buy_qty, sell_qty].min
        realized = matched.positive? ? ((sell_avg - buy_avg) * matched) : 0.0
        unrealized = net_qty.zero? ? 0.0 : (ltp - entry_for(net_qty, buy_avg, sell_avg)) * net_qty

        {
          exchange_segment: segment,
          security_id: security_id,
          net_qty: net_qty,
          buy_qty: buy_qty,
          sell_qty: sell_qty,
          buy_avg: buy_avg.round(2),
          sell_avg: sell_avg.round(2),
          ltp: ltp.to_f.round(2),
          realized_pnl: realized.round(2),
          unrealized_pnl: unrealized.round(2),
          charges: charges_for(fills).round(2)
        }
      end

      # A short position's unrealised P&L runs the other way, so the entry
      # reference is the sell average.
      def entry_for(net_qty, buy_avg, sell_avg)
        net_qty.positive? ? buy_avg : sell_avg
      end

      def weighted_average(fills)
        qty = fills.sum { |f| f.filled_qty.to_i }
        return 0.0 if qty.zero?

        fills.sum { |f| f.average_traded_price.to_f * f.filled_qty.to_i } / qty
      end

      def mark_price(segment, security_id)
        Live::RedisPnlCache.instance.ltp(segment: segment, security_id: security_id)
      rescue StandardError
        nil
      end

      # Real Dhan charges per fill, so a paper strategy is judged on the same
      # cost base as a live one.
      def charges_for(fills)
        fills.sum do |fill|
          Charges::Calculator.call(
            {
              'securityId' => fill.security_id,
              'exchangeSegment' => fill.exchange_segment,
              'productType' => fill.product_type
            },
            {
              entry_price: fill.average_traded_price.to_f,
              ltp: fill.average_traded_price.to_f,
              quantity: fill.filled_qty.to_i
            }
          ).to_f
        rescue StandardError => e
          Rails.logger.debug { "[Paper::Positions] charge calc failed for order #{fill.id}: #{e.message}" }
          0.0
        end
      end
    end
  end
end
