class TrimAndAddSignalTypeToAlerts < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    # Add `signal_type` first (safe operation)
    add_column :alerts, :signal_type, :string

    # Remove each column safely (skip if doesn't exist)
    remove_column :alerts, :high if column_exists?(:alerts, :high)
    remove_column :alerts, :low if column_exists?(:alerts, :low)
    remove_column :alerts, :volume if column_exists?(:alerts, :volume)
    remove_column :alerts, :stop_price if column_exists?(:alerts, :stop_price)
    remove_column :alerts, :take_profit if column_exists?(:alerts, :take_profit)
    remove_column :alerts, :trailing_stop_loss if column_exists?(:alerts, :trailing_stop_loss)
    remove_column :alerts, :limit_price if column_exists?(:alerts, :limit_price)
    remove_column :alerts, :stop_loss if column_exists?(:alerts, :stop_loss)
  end
end
