# frozen_string_literal: true

# Audit trail for scrip-master imports.
#
# The importer previously scribbled eight loose strings into `app_settings`
# ("instruments.last_imported_at", "instruments.last_derivative_rows", ...),
# which keeps only the most recent run, stores numbers as text and cannot
# record a failure at all — a crashed import looks exactly like one that never
# ran. One row per run keeps the history and makes staleness a query.
class CreateInstrumentSyncRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :instrument_sync_runs do |t|
      t.string :source, null: false, default: 'url'
      t.string :status, null: false, default: 'running'
      t.datetime :started_at, null: false
      t.datetime :finished_at

      t.integer :instrument_rows, null: false, default: 0
      t.integer :derivative_rows, null: false, default: 0
      t.integer :instrument_upserts, null: false, default: 0
      t.integer :derivative_upserts, null: false, default: 0
      t.integer :unparented_derivatives, null: false, default: 0
      t.integer :deactivated_rows, null: false, default: 0

      t.text :error_message

      t.timestamps
    end

    add_index :instrument_sync_runs, :started_at
    add_index :instrument_sync_runs, %i[status started_at]
  end
end
