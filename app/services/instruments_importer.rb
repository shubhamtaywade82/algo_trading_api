# frozen_string_literal: true

# Orchestrates a scrip-master import: fetch, parse, link derivatives to their
# underlying, upsert the four tables, retire whatever dropped out of the feed,
# and record the run.
class InstrumentsImporter < ApplicationService
  def self.import_from_url
    new.import_from_url
  end

  def self.import(file_path = nil)
    new.import(file_path)
  end

  def self.import_from_csv(csv_content)
    new.import_from_csv(csv_content)
  end

  def import_from_url
    run(source: 'url') { InstrumentsImport::Fetcher.call }
  end

  def import(file_path = nil)
    source = file_path ? 'file' : 'url'
    run(source: source) { InstrumentsImport::Fetcher.call(file_path: file_path) }
  end

  # Parses content the caller already has. Deliberately not tracked as a sync
  # run and does not retire anything: the caller may be passing a fixture or a
  # single segment, and treating a partial feed as authoritative would
  # deactivate every instrument it happens to omit.
  def import_from_csv(csv_content)
    process_csv(csv_content, deactivate_missing: false)
  end

  private

  def run(source:)
    started_at = Time.current
    sync_run = InstrumentSyncRun.create!(source: source, status: 'running', started_at: started_at)

    summary = process_csv(yield, deactivate_missing: true, started_at: started_at)

    sync_run.succeed!(**summary.slice(
      :instrument_rows, :derivative_rows, :instrument_upserts,
      :derivative_upserts, :unparented_derivatives, :deactivated_rows
    ))

    summary.merge(
      started_at: started_at,
      finished_at: sync_run.finished_at,
      duration: sync_run.duration,
      sync_run_id: sync_run.id
    )
  rescue StandardError => e
    # A crashed import used to be indistinguishable from one that never ran:
    # nothing was written until the very end.
    sync_run&.fail!(e.message)
    raise
  end

  def process_csv(csv_content, deactivate_missing:, started_at: Time.current)
    parsed = InstrumentsImport::Parser.call(csv_content)

    # Instruments first: derivatives are linked by the parent's primary key,
    # which does not exist until its row does.
    InstrumentsImport::Upserter.call(
      instruments_rows: parsed[:instruments],
      derivatives_rows: []
    )

    mapped = InstrumentsImport::Mapper.call(parsed[:derivatives])

    # Unparented contracts are imported too — instrument_id is nullable, and
    # dropping them made BSE index options unresolvable.
    upserts = InstrumentsImport::Upserter.call(
      instruments_rows: [],
      derivatives_rows: mapped[:with_parent] + mapped[:without_parent],
      order_features_rows: parsed[:order_features],
      margin_requirements_rows: parsed[:margin_requirements]
    )

    deactivated = if deactivate_missing
                    InstrumentsImport::Deactivator.call(started_at: started_at)[:deactivated_rows]
                  else
                    0
                  end

    {
      instrument_rows: parsed[:instruments].size,
      derivative_rows: parsed[:derivatives].size,
      instrument_upserts: parsed[:instruments].size,
      derivative_upserts: upserts[:derivative_upserts],
      order_feature_upserts: upserts[:order_feature_upserts],
      margin_requirement_upserts: upserts[:margin_requirement_upserts],
      unparented_derivatives: mapped[:without_parent].size,
      deactivated_rows: deactivated,
      instrument_total: Instrument.count,
      derivative_total: Derivative.count
    }
  end
end
