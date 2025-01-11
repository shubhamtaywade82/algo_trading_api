# frozen_string_literal: true

class Position < ApplicationRecord
  # Associations
  belongs_to :instrument

  # Enums
  enum :position_type, { long: 'LONG', short: 'SHORT', closed: 'CLOSED' }
  enum :product_type, { cnc: 'CNC', intraday: 'INTRADAY', margin: 'MARGIN', mtf: 'MTF', co: 'CO', bo: 'BO' }
  enum :exchange_segment,
       { nse_eq: 'NSE_EQ', nse_fno: 'NSE_FNO', bse_eq: 'BSE_EQ', bse_fno: 'BSE_FNO', mcx_comm: 'MCX_COMM' }
end
