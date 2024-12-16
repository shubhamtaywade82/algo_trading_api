class AddActionToAlerts < ActiveRecord::Migration[8.0]
  def change
    add_column :alerts, :action, :string
  end
end
