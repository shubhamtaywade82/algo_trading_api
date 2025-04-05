class TrimAndAddSignalTypeToAlerts < ActiveRecord::Migration[8.0]
  def change
    remove_column :alerts, :high, :decimal, precision: 15, scale: 2
    remove_column :alerts, :low, :decimal, precision: 15, scale: 2
    remove_column :alerts, :volume, :decimal, precision: 15, scale: 6
    remove_column :alerts, :stop_price, :decimal, precision: 15, scale: 2
    remove_column :alerts, :take_profit, :decimal, precision: 15, scale: 2
    remove_column :alerts, :trailing_stop_loss, :decimal, precision: 15, scale: 2
    remove_column :alerts, :limit_price, :decimal, precision: 15, scale: 2
    remove_column :alerts, :stop_loss, :decimal, precision: 15, scale: 2

    add_column :alerts, :signal_type, :string
  end
end
