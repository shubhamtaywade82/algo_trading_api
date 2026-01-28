# frozen_string_literal: true

# Mirrors algo_scalper_api lib/tasks/instruments.rake: import_from_url, summary output.
namespace :import do
  desc 'Import instruments and derivatives from DhanHQ CSV (uses 24h cache, upserts)'
  task instruments: :environment do
    puts 'Starting instruments import...'
    result = InstrumentsImporter.import_from_url
    puts "\nImport completed in #{result[:duration]&.round(2)} seconds."
    puts "Instruments: #{result[:instrument_upserts]} upserted, #{result[:instrument_total]} total"
    puts "Derivatives: #{result[:derivative_upserts]} upserted, #{result[:derivative_total]} total"
  rescue StandardError => e
    puts "Import failed: #{e.message}"
    puts e.backtrace.first(5).join("\n")
    raise
  end
end
