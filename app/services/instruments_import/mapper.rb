# frozen_string_literal: true

module InstrumentsImport
  # Handles mapping and linking of Derivatives to their underlying Instruments.
  class Mapper < ApplicationService
    def initialize(derivatives_rows)
      @derivatives_rows = derivatives_rows
    end

    def call
      lookup = build_instrument_lookup
      with_parent = []
      without_parent = []

      @derivatives_rows.each do |row|
        sym = row[:underlying_symbol].to_s.strip.upcase

        if sym.blank?
          without_parent << row
          next
        end

        parent_code = InstrumentTypeMapping.underlying_for(row[:instrument])
        key = [parent_code.to_s.upcase, sym]

        if (pid = lookup[key])
          row[:instrument_id] = pid
          with_parent << row
        else
          without_parent << row
        end
      end

      { with_parent: with_parent, without_parent: without_parent }
    end

    private

    def build_instrument_lookup
      Instrument.pluck(:id, :instrument, :underlying_symbol).each_with_object({}) do |(id, inst, sym), h|
        next if sym.blank?

        key = [inst.to_s.strip.upcase, sym.to_s.strip.upcase]
        h[key] = id
      end
    end
  end
end
