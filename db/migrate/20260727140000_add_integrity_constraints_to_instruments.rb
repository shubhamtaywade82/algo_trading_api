# frozen_string_literal: true

# Domain integrity for the two tables the whole trading path sizes and prices
# off. Both are written exclusively by `InstrumentsImport::Upserter` through
# activerecord-import, which skips model validations by design — so until now
# nothing but the parser stood between a malformed scrip-master row and a
# negative lot size sizing a live order.
#
# Constraints are added NOT VALID: they are enforced on every INSERT and UPDATE
# from here on (which is the point — the nightly import is the only writer),
# while rows that predate them are left alone rather than failing the deploy.
# `bin/rails instruments:validate_constraints` reports any legacy violations and
# promotes the constraints to fully validated once the table is clean.
#
# Deliberately *not* constrained:
#
#   • `tick_size > 0` — PriceMath rounds to a hardcoded 0.05 tick and never
#     divides by this column, so a zero tick is untidy feed data, not a
#     division hazard. A stricter rule would abort an entire import over one
#     odd row, which is far worse than storing it.
#   • uniqueness on `security_id` — a DhanHQ security_id is unique within an
#     exchange segment, not globally (NSE_EQ 2885 and IDX_I 2885 are different
#     instruments). The existing `index_instruments_unique` on
#     (security_id, symbol_name, exchange, segment) is the real key.
#   • uniqueness on `isin` — one ISIN spans a company's NSE and BSE listings
#     and every derivative written against it.
class AddIntegrityConstraintsToInstruments < ActiveRecord::Migration[8.0]
  # Applied to both instruments and derivatives: the columns are identical and
  # so are the invariants.
  CONSTRAINTS = {
    'lot_size_positive' => 'lot_size IS NULL OR lot_size > 0',
    'tick_size_non_negative' => 'tick_size IS NULL OR tick_size >= 0',
    'strike_price_non_negative' => 'strike_price IS NULL OR strike_price >= 0',
    'option_type_valid' => "option_type IS NULL OR option_type IN ('CE', 'PE')"
  }.freeze

  TABLES = %i[instruments derivatives].freeze

  def change
    TABLES.each do |table|
      CONSTRAINTS.each do |suffix, expression|
        add_check_constraint table, expression,
                             name: "chk_#{table}_#{suffix}",
                             validate: false
      end
    end

    # Supports the display_name arm of Instrument.lookup_by_symbol. DISPLAY_NAME
    # arrives title-cased from the feed ("Sensex", "Nifty 50") so the lookup
    # compares case-insensitively, and without a matching expression index that
    # arm is a sequential scan over the whole master on every symbol miss.
    add_index :instruments, 'UPPER(display_name)',
              name: 'index_instruments_on_upper_display_name',
              where: 'display_name IS NOT NULL'
  end
end
