# frozen_string_literal: true

class Holding < ApplicationRecord
  # Enums
  enum :exchange, { nse: 'NSE', bse: 'BSE', mcx: 'MCX' }
end
