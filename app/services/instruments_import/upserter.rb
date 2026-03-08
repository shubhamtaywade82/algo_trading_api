# frozen_string_literal: true

module InstrumentsImport
  # Handles the fast batch insertion/upserting of records into the database.
  class Upserter < ApplicationService
    BATCH_SIZE = 1_000

    def initialize(instruments_rows:, derivatives_rows:)
      @instruments_rows = instruments_rows
      @derivatives_rows = derivatives_rows
    end

    def call
      instrument_result = import_instruments!
      derivative_result = import_derivatives!

      {
        instrument_upserts: instrument_result&.ids&.size.to_i,
        derivative_upserts: derivative_result&.ids&.size.to_i
      }
    end

    private

    def import_instruments!
      return nil if @instruments_rows.empty?

      Instrument.import(
        @instruments_rows,
        batch_size: BATCH_SIZE,
        on_duplicate_key_update: {
          conflict_target: %i[security_id symbol_name exchange segment],
          columns: %i[display_name isin instrument instrument_type underlying_symbol series lot_size tick_size asm_gsm_flag
                      asm_gsm_category mtf_leverage updated_at]
        }
      )
    end

    def import_derivatives!
      return nil if @derivatives_rows.empty?

      # Filter out derivatives with invalid instrument_ids just in case
      valid_ids = Instrument.where(id: @derivatives_rows.filter_map { |r| r[:instrument_id] }.uniq).pluck(:id).to_set
      validated = @derivatives_rows.select { |r| r[:instrument_id] && valid_ids.include?(r[:instrument_id]) }
      return nil if validated.empty?

      Derivative.import(
        validated,
        batch_size: BATCH_SIZE,
        on_duplicate_key_update: {
          conflict_target: %i[security_id symbol_name exchange segment],
          columns: %i[display_name isin instrument instrument_type underlying_symbol underlying_security_id series expiry_date strike_price
                      option_type lot_size expiry_flag tick_size asm_gsm_flag instrument_id updated_at]
        }
      )
    end
  end
end
