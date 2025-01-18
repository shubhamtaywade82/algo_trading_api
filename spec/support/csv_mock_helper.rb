# frozen_string_literal: true

require 'csv'
require 'open-uri'

module CsvMockHelper
  MOCK_CSV_PATH = Rails.root.join('spec/fixtures/files/mock_instruments.csv')
  ORIGINAL_CSV_URL = 'https://images.dhan.co/api-data/api-scrip-master-detailed.csv'

  def generate_mock_csv
    return if File.exist?(MOCK_CSV_PATH)

    csv_data = URI.open(ORIGINAL_CSV_URL).read
    csv = CSV.parse(csv_data, headers: true)

    criteria = {
      'NSE' => {
        'C' => {
          'INDEX' => %w[NIFTY NIFTYFUTM1],
          'FUTCUR' => %w[USDINR GBPINR],
          'OPTCUR' => %w[USDINR EURINR]
        },
        'D' => {
          'FUTIDX' => %w[NIFTY BANKNIFTY],
          'FUTSTK' => %w[RELIANCE HDFCBANK],
          'OPTIDX' => %w[NIFTY BANKNIFTY],
          'OPTSTK' => %w[RELIANCE HDFCBANK]
        },
        'E' => {
          'EQUITY' => %w[RELIANCE HDFCBANK]
        },
        'I' => {
          'INDEX' => %w[NIFTY BANKNIFTY]
        }
      },
      'BSE' => {
        'C' => {
          'FUTCUR' => %w[USDINR GBPINR],
          'OPTCUR' => %w[USDINR EURINR]
        },
        'D' => {
          'FUTIDX' => %w[SENSEX SENSEX50],
          'FUTSTK' => %w[RELIANCE HDFCBANK],
          'OPTIDX' => %w[SENSEX SENSEX50],
          'OPTSTK' => %w[RELIANCE HDFCBANK]
        },
        'E' => {
          'EQUITY' => %w[RELIANCE HDFCBANK]
        },
        'I' => {
          'INDEX' => %w[SENSEX SENSEX50]
        }
      },
      'MCX' => {
        'M' => {
          'FUTCOM' => %w[GOLD SILVER],
          'FUTIDX' => %w[MCXMETLDEX MCXBULLDEX],
          'OPTFUT' => %w[GOLD SILVER]
        }
      }
    }

    filtered_rows = []
    criteria.each do |exch_id, segments|
      segments.each do |segment, instruments|
        instruments.each do |instrument, symbols|
          symbols.first(2).each do |symbol_name|
            csv_row = csv.find do |row|
              row['EXCH_ID'] == exch_id &&
                row['SEGMENT'] == segment &&
                row['INSTRUMENT'] == instrument &&
                row['UNDERLYING_SYMBOL'] == symbol_name
            end
            filtered_rows << csv_row if csv_row
          end
        end
      end
    end

    segments = csv.pluck('SEGMENT').uniq
    segments.each do |segment|
      next if filtered_rows.any? { |row| row['SEGMENT'] == segment }

      filtered_rows << CSV::Row.new(csv.headers, ['N/A'] * csv.headers.size).tap do |dummy_row|
        dummy_row['SEGMENT'] = segment
        dummy_row['EXCH_ID'] = 'N/A'
        dummy_row['INSTRUMENT'] = 'N/A'
        dummy_row['UNDERLYING_SYMBOL'] = 'N/A'
      end
    end

    CSV.open(MOCK_CSV_PATH, 'w') do |csv_out|
      csv_out << csv.headers.compact
      filtered_rows.each { |row| csv_out << row }
    end

    puts "Mock CSV created at: #{MOCK_CSV_PATH}"
  end
end
