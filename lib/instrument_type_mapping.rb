# frozen_string_literal: true

# Maps CSV instrument codes to underlying instrument codes for parent lookup
# Example: FUTIDX (Futures of Index) -> INDEX (the underlying index)
class InstrumentTypeMapping
  # Maps derivative instrument codes to their underlying instrument codes
  UNDERLYING_MAP = {
    'FUTIDX' => 'INDEX',   # Futures of Index -> Index
    'OPTIDX' => 'INDEX',   # Options of Index -> Index
    'FUTSTK' => 'EQUITY',  # Futures of Stock -> Equity
    'OPTSTK' => 'EQUITY',  # Options of Stock -> Equity
    'FUTCUR' => 'CURRENCY', # Futures of Currency -> Currency (if needed)
    'OPTCUR' => 'CURRENCY', # Options of Currency -> Currency (if needed)
    'FUTCOM' => 'COMMODITY', # Futures of Commodity -> Commodity (if needed)
    'OPTFUT' => 'COMMODITY'  # Options of Commodity -> Commodity (if needed)
  }.freeze

  def self.underlying_for(instrument_code)
    UNDERLYING_MAP[instrument_code.to_s.upcase] || instrument_code
  end
end

