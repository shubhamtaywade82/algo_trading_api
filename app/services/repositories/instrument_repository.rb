# frozen_string_literal: true

module Repositories
  class InstrumentRepository
    # Use segment: :index for index symbols (e.g. NIFTY) when the symbol exists in multiple segments.
    def self.find_by_symbol(symbol, segment: nil)
      base = [:index, 'index'].include?(segment) ? Instrument.segment_index : Instrument
      base.find_by(symbol_name: symbol) || base.find_by(underlying_symbol: symbol)
    end

    def self.active_instruments
      Instrument.where(active: true)
    end
  end
end
