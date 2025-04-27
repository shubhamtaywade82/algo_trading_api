class AddMetadataToAlerts < ActiveRecord::Migration[8.0]
  def change
    add_column :alerts, :metadata, :jsonb
  end
end
