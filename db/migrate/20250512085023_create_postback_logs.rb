class CreatePostbackLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :postback_logs do |t|
      t.bigint :order_id
      t.string :dhan_order_id
      t.string :event
      t.jsonb :payload

      t.timestamps
    end
  end
end
