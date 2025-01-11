# frozen_string_literal: true

module DhanhqMappings
  EXCHANGES = {
    'NSE' => 'National Stock Exchange',
    'BSE' => 'Bombay Stock Exchange',
    'MCX' => 'Multi Commodity Exchange'
  }.freeze

  # SEGMENTS = {
  #   "IDX_I" => "Index",
  #   "NSE_EQ" => "Equity Cash",
  #   "NSE_FNO" => "Futures & Options",
  #   "NSE_CURRENCY" => "Currency",
  #   "BSE_EQ" => "Equity Cash",
  #   "MCX_COMM" => "Commodity"
  # }.freeze

  SEGMENTS = {
    I: 'Index',
    E: 'Equity',
    D: 'Derivatives',
    C: 'Currency',
    M: 'Commodity'
  }.freeze

  PRODUCT_TYPES = {
    'CNC' => 'Cash & Carry',
    'INTRADAY' => 'Intraday',
    'MARGIN' => 'Carry Forward',
    'CO' => 'Cover Order',
    'BO' => 'Bracket Order'
  }.freeze

  ORDER_STATUSES = {
    'TRANSIT' => 'Did not reach the exchange server',
    'PENDING' => 'Awaiting execution',
    'REJECTED' => 'Rejected by broker/exchange',
    'CANCELLED' => 'Cancelled by user',
    'TRADED' => 'Executed successfully',
    'EXPIRED' => 'Validity expired'
  }.freeze

  INSTRUMENT_TYPES = {
    'INDEX' => 'Index',
    'FUTIDX' => 'Futures of Index',
    'OPTIDX' => 'Options of Index',
    'EQUITY' => 'Equity',
    'FUTSTK' => 'Futures of Stock',
    'OPTSTK' => 'Options of Stock'
  }.freeze

  EXPIRY_FLAGS = {
    'M' => 'Monthly Expiry',
    'W' => 'Weekly Expiry'
  }.freeze
end
