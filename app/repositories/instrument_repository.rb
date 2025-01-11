# frozen_string_literal: true

class InstrumentRepository
  def self.find_by_symbol(symbol)
    Instrument.find_by(symbol_name: symbol)
  end

  def self.active_instruments
    Instrument.where(active: true)
  end
end
