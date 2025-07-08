class CreateAppSettings < ActiveRecord::Migration[8.0]
  def change
    create_table :app_settings, id: false do |t|
      t.string :key, primary_key: true # eg "enable_percent_sl"
      t.string :value, null: false
      t.timestamps
    end
  end
end
