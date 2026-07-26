# frozen_string_literal: true

# The simulated trading book's account: virtual capital, margin and P&L.
#
# Single-row by convention, like DhanAccessToken — this app trades one Dhan
# account, so there is no user to scope by. Use {.current} rather than
# constructing one.
class PaperAccount < ApplicationRecord
  has_many :paper_orders, dependent: :destroy
  has_many :paper_positions, dependent: :destroy

  validates :name, presence: true
  validates :initial_capital, numericality: { greater_than: 0 }

  # Simulation knobs. Overridable per account via the `config` jsonb so a book
  # can be made pessimistic (wider slippage, lower fill rate) without code
  # changes.
  DEFAULT_CONFIG = {
    'slippage_model' => 'fixed_bps',   # fixed_bps | spread_based | volume_based | none
    'slippage_bps' => 5,
    'fill_probability' => 1.0,         # chance a resting order fills fully
    'partial_fill_enabled' => false,
    'partial_fill_min_pct' => 0.3,
    'margin_model' => 'simplified',
    'market_hours_enforced' => true
  }.freeze

  # @return [PaperAccount] the single account, created on first use
  def self.current
    first || create!(
      available_balance: 1_000_000,
      initial_capital: 1_000_000,
      config: DEFAULT_CONFIG.dup
    )
  end

  # @return [Hash] config with defaults filled in
  def settings
    DEFAULT_CONFIG.merge(config || {})
  end

  # Capital not committed to margin.
  # @return [BigDecimal]
  def free_margin
    available_balance - blocked_margin
  end

  # @return [Float] marked-to-market unrealised P&L across open positions
  def unrealized_pnl
    paper_positions.where.not(position_type: 'CLOSED').sum(:unrealized_profit).to_f
  end

  # @return [Float] capital including open-position marks, net of charges
  def current_capital
    initial_capital.to_f + realized_pnl.to_f + unrealized_pnl - total_charges.to_f
  end

  # Returns the book to its starting state, keeping the configured capital.
  def reset!
    transaction do
      paper_orders.destroy_all
      paper_positions.destroy_all
      update!(
        available_balance: initial_capital,
        utilized_margin: 0,
        blocked_margin: 0,
        realized_pnl: 0,
        total_charges: 0,
        reset_at: Time.current
      )
    end
  end
end
