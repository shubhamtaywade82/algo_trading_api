# frozen_string_literal: true

module InstrumentsImport
  # Retires rows the exchange has stopped listing.
  #
  # The importer only ever upserted, so every expired weekly option ever
  # downloaded stayed in `derivatives` as a tradable-looking contract, and a
  # delisted scrip still resolved to a security_id the gateway would happily
  # send an order for.
  #
  # Rows are flagged, never deleted: orders, positions, exit logs and position
  # trackers reference these instruments by security_id, and a delivery
  # position can outlive the contract's listing. Deleting would break the audit
  # trail for a position still open.
  class Deactivator < ApplicationService
    def initialize(started_at:)
      @started_at = started_at
    end

    def call
      # Anything not stamped by the run that just finished was absent from the
      # feed. `last_seen_at IS NULL` covers rows that predate the column.
      deactivated = [Instrument, Derivative].sum do |klass|
        # rubocop:disable Rails/SkipsModelValidations -- a bulk flag flip over
        # six-figure row counts; there is nothing to validate and instantiating
        # each row would make the sweep unusable.
        klass.active
          .where(last_seen_at: ...@started_at)
          .or(klass.active.where(last_seen_at: nil))
          .update_all(active: false, updated_at: Time.current)
        # rubocop:enable Rails/SkipsModelValidations
      end

      # A row that reappears in a later feed is reactivated by the upsert,
      # which writes `active: true` back.
      { deactivated_rows: deactivated }
    end
  end
end
