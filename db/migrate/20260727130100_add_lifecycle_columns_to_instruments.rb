# frozen_string_literal: true

# Gives instruments and derivatives a lifecycle and a first-class exchange segment.
#
# Three gaps this closes:
#
# 1. Nothing ever retired a row. The importer only upserts, so every expired
#    weekly option ever downloaded stays in `derivatives` forever, and a
#    contract the exchange has delisted still resolves to a tradable
#    security_id. `active` + `last_seen_at` let the importer mark rows that
#    dropped out of the feed without deleting rows that orders/positions still
#    reference by security_id.
#
# 2. `Repositories::InstrumentRepository.active_instruments` already queries
#    `Instrument.where(active: true)` against a column that does not exist, so
#    it raises on every call.
#
# 3. `exchange_segment` — the key every DhanHQ call and every WebSocket tick is
#    addressed by — was computed in Ruby from (exchange, segment), so it could
#    not be indexed or queried. As a stored generated column it is maintained
#    by Postgres, so it cannot drift from its inputs, and
#    `InstrumentHelpers#exchange_segment` already prefers `self[:exchange_segment]`
#    when present and picks it up for free.
class AddLifecycleColumnsToInstruments < ActiveRecord::Migration[8.0]
  # Mirrors InstrumentHelpers#exchange_segment. IDX_I intentionally covers both
  # NSE and BSE indices — that is DhanHQ's own segment, not a collapse on our side.
  EXCHANGE_SEGMENT_SQL = <<~SQL.squish
    CASE
      WHEN segment = 'I' AND exchange IN ('NSE', 'BSE') THEN 'IDX_I'
      WHEN segment = 'E' AND exchange = 'NSE' THEN 'NSE_EQ'
      WHEN segment = 'E' AND exchange = 'BSE' THEN 'BSE_EQ'
      WHEN segment = 'D' AND exchange = 'NSE' THEN 'NSE_FNO'
      WHEN segment = 'D' AND exchange = 'BSE' THEN 'BSE_FNO'
      WHEN segment = 'C' AND exchange = 'NSE' THEN 'NSE_CURRENCY'
      WHEN segment = 'C' AND exchange = 'BSE' THEN 'BSE_CURRENCY'
      WHEN segment = 'M' AND exchange = 'MCX' THEN 'MCX_COMM'
    END
  SQL

  def change
    %i[instruments derivatives].each do |table|
      add_column table, :active, :boolean, null: false, default: true
      add_column table, :last_seen_at, :datetime
      add_column table, :exchange_segment, :virtual,
                 type: :string, as: EXCHANGE_SEGMENT_SQL, stored: true
    end

    # Rows already in the table predate the feed, so treat them as seen at
    # migration time rather than leaving them instantly stale.
    reversible do |dir|
      dir.up do
        %w[instruments derivatives].each do |table|
          execute("UPDATE #{table} SET last_seen_at = updated_at WHERE last_seen_at IS NULL")
        end
      end
    end

    # A contract is tradable whether or not we have matched its underlying.
    # With NOT NULL, InstrumentsImport::Upserter silently dropped every
    # derivative whose underlying instrument was missing from the master —
    # BSE index options in particular — so they could never be resolved.
    change_column_null :derivatives, :instrument_id, true
  end
end
