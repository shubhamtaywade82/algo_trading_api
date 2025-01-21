# frozen_string_literal: true

module InstrumentEnums
  extend ActiveSupport::Concern

  included do
    enum :exchange, { nse: 'NSE', bse: 'BSE' }
    enum :segment, { index: 'I', equity: 'E', currency: 'C', derivatives: 'D' }, prefix: true
    enum :instrument, {
      index: 'INDEX',
      futures_index: 'FUTIDX',
      options_index: 'OPTIDX',
      equity: 'EQUITY',
      futures_stock: 'FUTSTK',
      options_stock: 'OPTSTK',
      futures_currency: 'FUTCUR',
      options_currency: 'OPTCUR'
    }, prefix: true
  end
end
