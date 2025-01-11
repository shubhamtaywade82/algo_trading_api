class UpdateAlertsTable < ActiveRecord::Migration[8.0]
  def change
    # Adding new columns
    add_column :alerts, :limit_price, :decimal, precision: 15, scale: 2
    add_column :alerts, :strategy_type, :string

    # Renaming existing column
    rename_column :alerts, :stop_loss, :stop_price
  end
end
