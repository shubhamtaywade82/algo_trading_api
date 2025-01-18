# frozen_string_literal: true

namespace :import do
  desc 'Import instruments from CSV'
  task instruments: :environment do
    puts 'Starting CSV import process...'

    # Dynamically download and import the CSV
    InstrumentsImporter.import

    puts 'CSV import completed successfully!'
  rescue StandardError => e
    puts "An error occurred during the import: #{e.message}"
    puts e.backtrace.join("\n")
  end
end
