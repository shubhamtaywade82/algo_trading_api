# frozen_string_literal: true

class AddIsinAndSeriesToDerivatives < ActiveRecord::Migration[8.0]
  def change
    add_column :derivatives, :isin, :string
    add_column :derivatives, :series, :string
  end
end
