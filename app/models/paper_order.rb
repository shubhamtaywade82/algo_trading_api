# frozen_string_literal: true

# A simulated order.
#
# Deliberately plain strings rather than enums: these mirror the DhanHQ API's
# own vocabulary ("TRADED", "BUY"), and an enum would read them back as
# lowercase keys, which is exactly the mismatch that bit the live `Order` model.
class PaperOrder < ApplicationRecord
  belongs_to :paper_account

  OPEN_STATUSES = %w[initiated pending part_traded].freeze
  CLOSED_STATUSES = %w[traded cancelled rejected expired closed].freeze

  scope :open_orders, -> { where(status: OPEN_STATUSES) }
  scope :resting, -> { where(status: %w[pending part_traded]) }
  scope :filled, -> { where(status: %w[traded part_traded closed]) }
  scope :super_orders, -> { where(order_category: 'super') }

  validates :security_id, :transaction_type, :order_type, :exchange_segment, presence: true
  validates :quantity, numericality: { greater_than: 0 }

  def buy?
    transaction_type.to_s.casecmp('BUY').zero?
  end

  def sell?
    !buy?
  end

  def open?
    OPEN_STATUSES.include?(status)
  end

  def resting?
    %w[pending part_traded].include?(status)
  end

  # Quantity still to be filled.
  # @return [Integer]
  def unfilled_qty
    quantity.to_i - filled_qty.to_i
  end

  # The side that closes this position.
  # @return [String]
  def opposite_side
    buy? ? 'SELL' : 'BUY'
  end
end
