class AddOmsErrorFieldsToOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :orders, :oms_error_code, :string
    add_column :orders, :oms_error_description, :string
  end
end
