class CreateSegments < ActiveRecord::Migration[8.0]
  def change
    create_table :segments do |t|
      t.string :segment_code
      t.string :description

      t.timestamps
    end
  end
end
