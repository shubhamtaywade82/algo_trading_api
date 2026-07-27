# frozen_string_literal: true

# Tracks which trading day the simulated book has already been rolled and
# squared off for, so both are idempotent no matter how often the tick stream
# asks.
class AddSessionDatesToPaperAccounts < ActiveRecord::Migration[8.0]
  def change
    change_table :paper_accounts, bulk: true do |t|
      t.date :last_rolled_on
      t.date :last_squared_off_on
    end
  end
end
