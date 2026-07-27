# frozen_string_literal: true

# Per-instrument tradability facts from the scrip master: whether bracket and
# cover orders are accepted, which sides may be traded, the exchange's ASM/GSM
# surveillance status and the MTF leverage on offer.
#
# Owned polymorphically by Instrument and Derivative — these columns used to be
# duplicated onto both wide tables and left almost entirely NULL.
class OrderFeature < ApplicationRecord
  # Associations
  belongs_to :featureable, polymorphic: true

  # Validations
  validates :bracket_flag, :cover_flag, inclusion: { in: %w[Y N] }, allow_nil: true
  # The exchange reports R for "removed from surveillance", which is not the
  # same as never having been listed.
  validates :asm_gsm_flag, inclusion: { in: %w[Y N R] }, allow_nil: true
  validates :featureable_id, uniqueness: { scope: :featureable_type }

  scope :bracket_allowed, -> { where(bracket_flag: 'Y') }
  scope :cover_allowed, -> { where(cover_flag: 'Y') }
  # 'R' means the exchange lifted the restriction, so it is tradable.
  scope :unrestricted, -> { where(asm_gsm_flag: [nil, 'N', 'R']) }

  def bracket_order_allowed?
    bracket_flag == 'Y'
  end

  def cover_order_allowed?
    cover_flag == 'Y'
  end

  def surveillance_restricted?
    asm_gsm_flag == 'Y'
  end
end
