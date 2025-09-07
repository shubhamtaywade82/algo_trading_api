# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InstrumentsImporter, type: :service do
  include CsvMockHelper

  let(:mock_csv_path) { CsvMockHelper::MOCK_CSV_PATH }

  before do
    # Ensure the mock CSV is generated before tests
    generate_mock_csv
  end

  describe '.import' do
    context 'when file_path is provided' do
      it 'imports data from the provided CSV file' do
        # Adjust count to match mock data
        expect do
          described_class.import(mock_csv_path)
        end.to change(Instrument, :count).by(24)
        expect(Instrument.find_by(symbol_name: 'NIFTY')).to be_present
        expect(Instrument.find_by(symbol_name: 'USDINR')).to be_present
        expect(Instrument.find_by(symbol_name: 'GOLD')).to be_present
      end
    end

    context 'when file_path is not provided' do
      before do
        allow(described_class).to receive(:download_csv).and_return(mock_csv_path)
      end

      it 'downloads the CSV and imports data' do
        expect(described_class).to receive(:download_csv)
        expect { described_class.import }.to change(Instrument, :count).by(24)
      end
    end
  end

  describe '.valid_instrument?' do
    it 'filters rows based on valid criteria' do
      csv_data = CSV.read(mock_csv_path, headers: true)
      valid_data = csv_data.select { |row| described_class.valid_instrument?(row) }

      expect(valid_data.size).to eq(40) # Adjust count to match filtered data
      expect(valid_data.pluck('SYMBOL_NAME')).to include('NIFTY', 'USDINR', 'GOLD')
    end
  end

  describe '.valid_instrument?' do
    it 'returns true for valid rows' do
      valid_row = CSV.read(mock_csv_path, headers: true).first
      expect(described_class).to be_valid_instrument(valid_row)
    end

    it 'returns false for invalid rows' do
      invalid_row = CSV::Row.new(
        %w[SECURITY_ID SYMBOL_NAME EXCH_ID SEGMENT INSTRUMENT LOT_SIZE],
        ['123', 'TEST', 'INVALID', 'E', 'EQUITY', 1]
      )
      expect(described_class).not_to be_valid_instrument(invalid_row)
    end
  end

  describe '.import_instruments' do
    it 'imports instruments correctly' do
      csv_data = CSV.read(mock_csv_path, headers: true)
      described_class.import_instruments(csv_data)

      expect(Instrument.find_by(symbol_name: 'NIFTY')).to be_present
      expect(Instrument.find_by(symbol_name: 'USDINR')).to be_present
    end
  end

  describe '.import_derivatives' do
    it 'imports derivatives correctly' do
      csv_data = CSV.read(mock_csv_path, headers: true)

      # Create the required instruments first
      nifty_instrument = create(:instrument, symbol_name: 'NIFTY', security_id: '9999', exchange: 'NSE')
      usdinr_instrument = create(:instrument, symbol_name: 'USDINR', security_id: '9998', exchange: 'NSE')

      instrument_mapping = { 'NIFTY-NSE' => nifty_instrument.id, 'USDINR-NSE' => usdinr_instrument.id }
      described_class.import_derivatives(csv_data, instrument_mapping)

      # Check that derivatives were created (exact strike prices depend on test data)
      expect(Derivative.count).to be > 0
    end
  end
end
