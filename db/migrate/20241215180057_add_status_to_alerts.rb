class AddStatusToAlerts < ActiveRecord::Migration[8.0]
  def change
    add_column :alerts, :status, :string, default: "pending", null: false
  end
end
