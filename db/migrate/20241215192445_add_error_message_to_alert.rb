class AddErrorMessageToAlert < ActiveRecord::Migration[8.0]
  def change
    add_column :alerts, :error_message, :text
  end
end
