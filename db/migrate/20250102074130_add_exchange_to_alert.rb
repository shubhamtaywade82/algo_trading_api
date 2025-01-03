class AddExchangeToAlert < ActiveRecord::Migration[8.0]
  def change
    add_column :alerts, :exchange, :string
  end
end
