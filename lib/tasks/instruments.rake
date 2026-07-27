# frozen_string_literal: true

namespace :instruments do
  desc 'Import instruments from DhanHQ CSV'
  task import: :environment do
    pp 'Starting instruments import...'
    start_time = Time.current

    begin
      result   = InstrumentsImporter.import_from_url
      duration = result[:duration] || (Time.current - start_time)
      pp "\nImport completed successfully in #{duration.round(2)} seconds!"
      pp "Total Instruments: #{result[:instrument_total]}"
      pp "Total Derivatives: #{result[:derivative_total]}"

      # Show some stats
      pp "\n--- Stats ---"
      pp "NSE Instruments: #{Instrument.nse.count}"
      pp "BSE Instruments: #{Instrument.bse.count}"
      pp "NSE Derivatives: #{Derivative.nse.count}"
      pp "BSE Derivatives: #{Derivative.bse.count}"
      pp "Options: #{Derivative.where(option_type: %w[CE PE]).count}"
      pp "Futures: #{Derivative.where(option_type: nil).where.not(expiry_date: nil).count}"
      pp "Instruments: #{Instrument.count}"
      pp "Derivatives: #{Derivative.count}"
      pp "TOTAL: #{Instrument.count + Derivative.count}"
    rescue StandardError => e
      pp "Import failed: #{e.message}"
      pp e.backtrace.join("\n")
    end
  end

  desc 'Reimport instruments and derivatives (upserts - adds new, updates existing, preserves positions)'
  task reimport: :environment do
    pp 'Starting instruments reimport (upsert mode)...'
    pp 'Note: Import uses upsert logic - will add new contracts and update existing ones.'
    pp 'Existing instruments/derivatives will NOT be deleted, so positions remain safe.'
    pp ''
    Rake::Task['instruments:import'].invoke
  end

  desc 'Clear all instruments and derivatives (DANGER: Will fail if active positions exist)'
  desc 'Only use this if you need to completely reset the database. Normal imports use upsert and do not require clearing.'
  task :clear, [:force] => :environment do |_t, args|
    pp '⚠️  WARNING: This will delete ALL instruments and derivatives!'
    pp '⚠️  This is usually NOT needed since imports use upsert (add/update only).'
    pp ''

    # Check for active position trackers that reference instruments (if PositionTracker exists)
    if defined?(PositionTracker)
      active_trackers = PositionTracker.where(status: PositionTracker::STATUSES[:active]) if PositionTracker.respond_to?(:where)
      if active_trackers&.any?
        pp "ERROR: Found #{active_trackers.count} active position tracker(s) that reference instruments."
        pp 'Active trackers:'
        active_trackers.limit(10).each do |tracker|
          pp "  - Order: #{tracker.order_no}, Instrument ID: #{tracker.instrument_id}, Status: #{tracker.status}, Symbol: #{tracker.symbol}"
        end

        pp ''
        if args[:force] == 'true'
          pp "FORCE mode enabled: Marking active position trackers as 'closed'..."
          # rubocop:disable Rails/SkipsModelValidations -- bulk close, callbacks would re-open trackers
          active_trackers.update_all(
            status: PositionTracker::STATUSES[:closed],
            updated_at: Time.current
          )
          # rubocop:enable Rails/SkipsModelValidations
          pp "Marked #{active_trackers.count} active tracker(s) as closed."
        else
          pp 'To force clear (will mark active positions as closed), run:'
          pp '  bin/rails instruments:clear[true]'
          pp 'Or manually close/exit positions first.'
          pp ''
          pp '💡 TIP: You probably don\'t need to clear - just run `bin/rails instruments:reimport`'
          pp '    which uses upsert and safely adds/updates without deleting.'
          raise 'Cannot clear instruments while active position trackers exist'
        end
      end

      # Delete inactive/closed trackers that reference instruments (to avoid FK constraint issues)
      inactive_trackers = PositionTracker.where.not(status: PositionTracker::STATUSES[:active]) if PositionTracker.respond_to?(:where)
      if inactive_trackers&.any?
        pp "Found #{inactive_trackers.count} inactive/closed position tracker(s)."
        if args[:force] == 'true'
          pp 'FORCE mode: Deleting inactive trackers to avoid FK constraints...'
          inactive_trackers.delete_all
          pp "Deleted #{inactive_trackers.count} inactive tracker(s)."
        else
          pp 'These will cause FK constraint errors. To delete them, use force mode:'
          pp '  bin/rails instruments:clear[true]'
          pp '⚠️  Or they will prevent instrument deletion.'
        end
      end
    end

    pp ''
    pp 'Proceeding with deletion of all instruments and derivatives...'
    # Now safe to delete derivatives and instruments
    Derivative.delete_all
    Instrument.delete_all
    pp '✅ Cleared successfully!'
  end

  desc 'Check instrument inventory freshness and counts'
  task status: :environment do
    # Reads instrument_sync_runs. This previously read a `Setting` constant
    # that does not exist in this app (the model is AppSetting) and compared
    # against InstrumentsImporter::CACHE_MAX_AGE, which lives on
    # InstrumentsImport::Fetcher — so the task raised NameError either way.
    run = InstrumentSyncRun.last_success

    unless run
      pp 'No successful instrument import recorded yet.'
      failed = InstrumentSyncRun.status_failed.recent.first
      pp "Last failure at #{failed.started_at}: #{failed.error_message}" if failed
      exit 1
    end

    age_seconds = Time.current - run.finished_at

    pp "Last import at: #{run.finished_at}"
    pp "Age (seconds): #{age_seconds.round(2)}"
    pp "Import duration (sec): #{run.duration&.round(2)}"
    pp "Last instrument rows: #{run.instrument_rows}"
    pp "Last derivative rows: #{run.derivative_rows}"
    pp "Upserts (instruments): #{run.instrument_upserts}"
    pp "Upserts (derivatives): #{run.derivative_upserts}"
    pp "Unparented derivatives: #{run.unparented_derivatives}"
    pp "Deactivated rows: #{run.deactivated_rows}"
    pp "Total instruments: #{Instrument.count} (#{Instrument.active.count} active)"
    pp "Total derivatives: #{Derivative.count} (#{Derivative.active.count} active)"

    if InstrumentSyncRun.stale?
      pp "Status: STALE (older than #{InstrumentSyncRun::STALE_AFTER.inspect})"
      exit 1
    end

    pp 'Status: OK'
  end
end

# Provide aliases for legacy singular namespace usage.
namespace :instrument do
  desc 'Alias for instruments:import'
  task import: 'instruments:import'

  desc 'Alias for instruments:clear'
  task clear: 'instruments:clear'

  desc 'Alias for instruments:reimport'
  task reimport: 'instruments:reimport'
end

