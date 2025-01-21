# frozen_string_literal: true

require 'csv'
require 'open-uri'

module TestInstrumentsImporter
  MAIN_CSV_URL = 'https://images.dhan.co/api-data/api-scrip-master-detailed.csv'
  MIS_CSV_PATH = Rails.root.join('mis_data.csv')
  MAIN_DOWNLOADED_FILE = Rails.root.join('tmp/large_master.csv')
  MAIN_FILTERED_CSV_PATH = Rails.root.join('tmp/test_data_filtered.csv')
  MIS_FILTERED_CSV_PATH = Rails.root.join('tmp/test_mis_data_filtered.csv')

  # Columns for combined uniqueness in the main CSV
  COMBINED_UNIQUENESS_COLUMNS = %w[
    EXCH_ID SEGMENT INSTRUMENT INSTRUMENT_TYPE SERIES OPTION_TYPE TICK_SIZE
  ].freeze

  # Additional filtering criteria for the main CSV
  FIELD_VALIDATIONS = {
    'LOT_SIZE' => ->(value) { value.to_i >= 0 },
    'STRIKE_PRICE' => ->(value) { value.to_f >= 0 }
  }.freeze

  # Prepare both main and MIS test CSVs
  def self.prepare_test_csvs
    prepare_main_csv
    prepare_mis_csv
  end

  # Ensure the main CSV is ready
  def self.prepare_main_csv
    if File.exist?(MAIN_FILTERED_CSV_PATH)
      puts "Filtered test CSV for main data already exists at #{MAIN_FILTERED_CSV_PATH}"
    else
      puts 'Creating filtered test CSV for main data...'
      ensure_main_csv_downloaded
      create_filtered_main_csv
    end
  end

  # Download the main CSV if not already present
  def self.ensure_main_csv_downloaded
    if File.exist?(MAIN_DOWNLOADED_FILE)
      puts "Main CSV already exists at #{MAIN_DOWNLOADED_FILE}, using the local copy."
    else
      puts "Downloading main CSV from #{MAIN_CSV_URL}..."
      File.write(MAIN_DOWNLOADED_FILE, URI.open(MAIN_CSV_URL).read)
      puts "Downloaded and saved as #{MAIN_DOWNLOADED_FILE}"
    end
  end

  # Create a filtered main CSV for testing
  def self.create_filtered_main_csv
    puts 'Filtering the main CSV...'
    csv_data = CSV.read(MAIN_DOWNLOADED_FILE, headers: true)
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

    CSV.open(MAIN_FILTERED_CSV_PATH, 'w') do |csv|
      csv << filtered_data.first.headers
      filtered_data.each { |row| csv << row }
    end

    puts "Filtered test CSV for main data created at #{MAIN_FILTERED_CSV_PATH}"
  end

  # Validate specific fields in the main CSV
  def self.valid_row?(row)
    FIELD_VALIDATIONS.all? do |field, validation|
      value = row[field]
      value.nil? || value.strip.empty? || validation.call(value)
    end
  end

  # Process and filter MIS details CSV
  def self.prepare_mis_csv
    if File.exist?(MIS_FILTERED_CSV_PATH)
      puts "Filtered test CSV for MIS details already exists at #{MIS_FILTERED_CSV_PATH}"
    else
      puts 'Creating filtered test CSV for MIS details...'
      create_filtered_mis_csv
    end
  end

  # Create a filtered MIS CSV for testing
  def self.create_filtered_mis_csv
    unless File.exist?(MIS_CSV_PATH)
      puts "MIS CSV not found at #{MIS_CSV_PATH}. Please ensure the file is available."
      return
    end

    puts "Filtering MIS CSV from #{MIS_CSV_PATH}..."
    csv_data = CSV.read(MIS_CSV_PATH, headers: true)
    filtered_data = []

    csv_data.each do |row|
      # Skip rows with missing critical data
      next if row['Symbol / Scrip Name'].blank?

      # Add the row to filtered data
      filtered_data << row
    end

    CSV.open(MIS_FILTERED_CSV_PATH, 'w') do |csv|
      csv << filtered_data.first.headers
      filtered_data.each { |row| csv << row }
    end

    puts "Filtered test CSV for MIS details created at #{MIS_FILTERED_CSV_PATH}"
  end

  # Import both main and MIS test data into the test database
  def self.import_to_test_db
    puts 'Importing filtered CSV data into the test database...'

    # Import the main CSV data
    CSV.read(MAIN_FILTERED_CSV_PATH, headers: true)
    InstrumentsImporter.import_csv_data(MAIN_FILTERED_CSV_PATH)

    # Import the MIS details CSV data
    mis_csv_data = CSV.read(MIS_FILTERED_CSV_PATH, headers: true)
    import_mis_data(mis_csv_data)

    print_import_summary

    puts 'Test data imported successfully.'
  end

  # Import MIS details into the test database
  def self.import_mis_data(mis_csv_data)
    mis_csv_data.each do |row|
      next if row['Symbol / Scrip Name'].blank?

      instruments = Instrument.where(underlying_symbol: row['Symbol / Scrip Name'], isin: row['ISIN'])
      instruments.each do |instrument|
        mis_detail = MisDetail.find_or_initialize_by(instrument: instrument)
        mis_detail.update!(
          isin: row['ISIN'],
          mis_leverage: row['MIS(Intraday)']&.delete('x')&.to_i,
          bo_leverage: row['BO(Bracket)']&.delete('x')&.to_i,
          co_leverage: row['CO(Cover)']&.delete('x')&.to_i
        )
      end
    end
  end

  # Print import summary for verification
  def self.print_import_summary
    puts "\n=== Import Summary ==="
    print_instrument_summary
    print_derivative_summary
    print_margin_requirement_summary
    print_order_feature_summary
    print_mis_detail_summary
    puts "\n======================="
  end

  def self.print_instrument_summary
    puts 'Instruments:'
    puts "  Total Instruments: #{Instrument.count}"
    puts '  By Segment:'
    Instrument.group(:segment).count.each do |segment, count|
      puts "    Segment: #{segment} => #{count} Instruments"
    end
    puts '  By Exchange:'
    Instrument.group(:exchange).count.each do |exchange, count|
      puts "    Exchange: #{exchange} => #{count} Instruments"
    end
  end

  def self.print_derivative_summary
    puts "\nDerivatives:"
    puts "  Total Derivatives: #{Derivative.count}"
    puts '  By Option Type and Expiry Date:'
    Derivative.group(:option_type, :expiry_date).count.each do |(type, expiry), count|
      puts "    Option Type: #{type}, Expiry: #{expiry} => #{count} Derivatives"
    end
  end

  def self.print_margin_requirement_summary
    puts "\nMargin Requirements:"
    puts "  Total Margin Requirements: #{MarginRequirement.count}"
    puts '  By Instrument Type:'
    MarginRequirement.joins(:instrument)
                     .group('instruments.instrument_type')
                     .count.each do |type, count|
      puts "    Instrument Type: #{type} => #{count} Margin Requirements"
    end
  end

  def self.print_order_feature_summary
    puts "\nOrder Features:"
    puts "  Total Order Features: #{OrderFeature.count}"
    puts '  By Bracket Flag:'
    OrderFeature.group(:bracket_flag).count.each do |flag, count|
      puts "    Bracket Flag: #{flag} => #{count} Order Features"
    end
  end

  def self.print_mis_detail_summary
    puts "\nMIS Details:"
    puts "  Total MIS Details: #{MisDetail.count}"
    puts '  By Leverage Types:'
    MisDetail.group(:mis_leverage, :bo_leverage, :co_leverage).count.each do |(mis, bo, co), count|
      puts "    MIS Leverage: #{mis}, BO Leverage: #{bo}, CO Leverage: #{co} => #{count} MIS Details"
    end
  end
end

# Prepare and import test data before tests run
RSpec.configure do |config|
  # config.before(:suite) do
  #   TestInstrumentsImporter.prepare_test_csvs
  #   TestInstrumentsImporter.import_to_test_db
  # end
end
