# frozen_string_literal: true

# Simulated trading book: account, orders and positions.
#
# Single-account by design, matching the rest of this app — there is no `user`
# to scope by, and `DhanAccessToken` already follows the same one-row pattern.
#
# Kept in dedicated tables rather than reusing `orders`: a simulated order
# carries state a real one does not (resting quantity, per-fill breakdown,
# rejection reasons, super-order legs), and mixing the two risks a paper fill
# being read as a real position.
class CreatePaperAccounts < ActiveRecord::Migration[8.0]
  def change
    create_table :paper_accounts do |t|
      t.string :name, null: false, default: 'Default Paper Account'
      t.decimal :initial_capital, precision: 14, scale: 2, null: false, default: 1_000_000
      t.decimal :available_balance, precision: 14, scale: 2, null: false, default: 1_000_000
      t.decimal :utilized_margin, precision: 14, scale: 2, null: false, default: 0
      t.decimal :blocked_margin, precision: 14, scale: 2, null: false, default: 0
      t.decimal :realized_pnl, precision: 14, scale: 2, null: false, default: 0
      t.decimal :total_charges, precision: 14, scale: 2, null: false, default: 0
      t.string :status, null: false, default: 'active'
      t.jsonb :config, null: false, default: {}
      t.datetime :reset_at
      t.timestamps
    end

    create_table :paper_orders do |t|
      t.references :paper_account, null: false, foreign_key: true
      t.string :correlation_id
      t.string :status, null: false, default: 'initiated'
      t.string :transaction_type, null: false
      t.string :exchange_segment, null: false
      t.string :product_type, null: false
      t.string :order_type, null: false
      t.string :validity, default: 'DAY'
      t.string :security_id, null: false
      t.string :trading_symbol
      t.integer :quantity, null: false
      t.integer :filled_qty, null: false, default: 0
      t.integer :remaining_quantity
      t.decimal :price, precision: 15, scale: 4
      t.decimal :trigger_price, precision: 15, scale: 4
      t.decimal :average_traded_price, precision: 15, scale: 4
      t.decimal :slippage_applied, precision: 15, scale: 4, default: 0
      t.decimal :charges, precision: 12, scale: 4, default: 0
      t.string :order_category, null: false, default: 'regular'
      t.jsonb :super_order_params
      t.jsonb :fill_details, null: false, default: []
      t.jsonb :rejection_reason
      t.jsonb :metadata, null: false, default: {}
      t.datetime :placed_at
      t.datetime :filled_at
      t.datetime :cancelled_at
      t.timestamps
    end

    # Resting-order matching scans by security on every tick, so this pair
    # carries the hot path.
    add_index :paper_orders, %i[security_id status]
    add_index :paper_orders, %i[paper_account_id status]
    add_index :paper_orders, :correlation_id

    create_table :paper_positions do |t|
      t.references :paper_account, null: false, foreign_key: true
      t.string :security_id, null: false
      t.string :trading_symbol
      t.string :exchange_segment, null: false
      t.string :product_type, null: false
      t.string :position_type, null: false, default: 'CLOSED'
      t.integer :net_qty, null: false, default: 0
      t.integer :buy_qty, null: false, default: 0
      t.integer :sell_qty, null: false, default: 0
      t.decimal :buy_avg, precision: 15, scale: 4, default: 0
      t.decimal :sell_avg, precision: 15, scale: 4, default: 0
      t.decimal :ltp, precision: 15, scale: 4
      t.decimal :realized_profit, precision: 14, scale: 2, null: false, default: 0
      t.decimal :unrealized_profit, precision: 14, scale: 2, null: false, default: 0
      t.decimal :margin_used, precision: 14, scale: 2, null: false, default: 0
      t.timestamps
    end

    add_index :paper_positions, %i[paper_account_id security_id product_type],
              unique: true, name: 'idx_paper_pos_acct_sec_prod'
  end
end
