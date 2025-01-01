namespace :csv do
  desc "Import instruments from CSV"
  task import: :environment do
    begin
      puts "Starting CSV import process..."

      # Dynamically download and import the CSV
      CsvImporter.import

      puts "CSV import completed successfully!"
    rescue StandardError => e
      puts "An error occurred during the import: #{e.message}"
      puts e.backtrace.join("\n")
    end
  end
end
