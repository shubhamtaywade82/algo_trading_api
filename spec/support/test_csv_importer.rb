# frozen_string_literal: true

require 'csv'
require 'open-uri'

module TestCsvImporter
  # Instruments
  CSV_URL = 'https://images.dhan.co/api-data/api-scrip-master-detailed.csv'
  DOWNLOADED_FILE = Rails.root.join('tmp/large_master.csv')
  FILTERED_CSV_PATH = Rails.root.join('tmp/test_data_filtered.csv')

  # MIS Details
  MIS_CSV_PATH = Rails.root.join('mis_data.csv')
  MIS_FILTERED_CSV_PATH = Rails.root.join('tmp/test_mis_data_filtered.csv')

  # Columns for combined uniqueness
  COMBINED_UNIQUENESS_COLUMNS = %w[
    EXCH_ID SEGMENT INSTRUMENT INSTRUMENT_TYPE SERIES OPTION_TYPE TICK_SIZE
  ].freeze

  # Additional filtering criteria
  FIELD_VALIDATIONS = {
    'LOT_SIZE' => ->(value) { value.to_i >= 0 },
    'STRIKE_PRICE' => ->(value) { value.to_f >= 0 }
  }.freeze

  # Ensure the filtered CSV is ready
  def self.prepare_test_csv
    if File.exist?(FILTERED_CSV_PATH)
      puts "Filtered test CSV already exists at #{FILTERED_CSV_PATH}"
    else
      puts 'Creating filtered test CSV...'
      ensure_csv_downloaded
      create_filtered_csv
    end
  end

  # Download the CSV if it doesn't already exist
  def self.ensure_csv_downloaded
    if File.exist?(DOWNLOADED_FILE)
      puts "Large CSV already exists at #{DOWNLOADED_FILE}, using the local copy."
    else
      puts "Downloading CSV from #{CSV_URL}..."
      File.write(DOWNLOADED_FILE, URI.open(CSV_URL).read)
      puts "Downloaded and saved as #{DOWNLOADED_FILE}"
    end
  end

  # Create a filtered CSV for testing
  def self.create_filtered_csv
    puts 'Filtering the CSV...'
    csv_data = CSV.read(DOWNLOADED_FILE, headers: true)
    unique_combinations = {}
    filtered_data = []

    csv_data.each do |row|
      # Create a combination key for uniqueness
      combination_key = COMBINED_UNIQUENESS_COLUMNS.map { |col| row[col] || 'NULL' }.join('|')

      # Skip non-unique rows or invalid rows
      next if unique_combinations.key?(combination_key) || !valid_row?(row)

      # Mark the combination as unique and add the row
      unique_combinations[combination_key] = true
      filtered_data << row
    end

    CSV.open(FILTERED_CSV_PATH, 'w') do |csv|
      csv << filtered_data.first.headers
      filtered_data.each { |row| csv << row }
    end

    puts "Filtered test CSV created at #{FILTERED_CSV_PATH}"
  end

  # Validate additional fields
  def self.valid_row?(row)
    FIELD_VALIDATIONS.all? do |field, validation|
      value = row[field]
      value.nil? || value.strip.empty? || validation.call(value)
    end
  end

  # Import the filtered CSV data into the test database
  def self.import_to_test_db
    puts 'Importing filtered CSV data into the test database...'
    # CSV.read(FILTERED_CSV_PATH, headers: true)

    # Reuse the CsvImporter logic for importing records
    CsvImporter.import_csv_data(FILTERED_CSV_PATH)
    puts 'Test data imported successfully.'
  end
end

# Prepare and import test data before tests run
RSpec.configure do |config|
  config.before(:suite) do
    TestCsvImporter.prepare_test_csv
    TestCsvImporter.import_to_test_db
  end
end
