class AddExchangeSegmentToInstrument < ActiveRecord::Migration[8.0]
  def change
    add_reference :instruments, :exchange_segment, null: false, foreign_key: true
  end
end
