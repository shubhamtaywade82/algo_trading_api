# frozen_string_literal: true

# A simulated position, maintained incrementally as fills arrive.
#
# Unlike the derived view this replaces, state is stored so margin can be
# blocked and released against it and so a mark-to-market survives a restart.
class PaperPosition < ApplicationRecord
  belongs_to :paper_account

  LONG = 'LONG'
  SHORT = 'SHORT'
  CLOSED = 'CLOSED'

  scope :open_positions, -> { where.not(position_type: CLOSED) }

  validates :security_id, :exchange_segment, :product_type, presence: true

  def long?
    position_type == LONG
  end

  def short?
    position_type == SHORT
  end

  def closed?
    position_type == CLOSED
  end

  # Entry reference for marking: a short marks against its sell average.
  # @return [Float]
  def entry_price
    (net_qty.to_i.negative? ? sell_avg : buy_avg).to_f
  end

  # Recomputes net quantity and side from the buy/sell legs.
  def recalculate_net!
    self.net_qty = buy_qty.to_i - sell_qty.to_i
    self.position_type =
      case net_qty <=> 0
      when 1 then LONG
      when -1 then SHORT
      else CLOSED
      end
  end

  # Marks the open leg against a live price.
  #
  # @param price [Numeric] current LTP
  # @return [Float] unrealised P&L
  def mark_to_market!(price)
    return 0.0 if price.blank?

    self.ltp = price
    self.unrealized_profit = net_qty.zero? ? 0.0 : (price.to_f - entry_price) * net_qty.to_i
    save!
    unrealized_profit.to_f
  end
end
