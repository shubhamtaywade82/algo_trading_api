# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CsvImporter, type: :service do
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
        end.to change(Instrument, :count).by(20)
        expect(Instrument.find_by(symbol_name: 'NIFTY')).to be_present
        expect(Instrument.find_by(symbol_name: 'USDINR')).to be_present
        expect(Instrument.find_by(symbol_name: 'RELIANCE')).to be_present
        expect(Instrument.find_by(symbol_name: 'GOLD')).to be_present
      end
    end

    context 'when file_path is not provided' do
      before do
        allow(described_class).to receive(:download_csv).and_return(mock_csv_path)
      end

      it 'downloads the CSV and imports data' do
        expect(described_class).to receive(:download_csv)
        expect { described_class.import }.to change(Instrument, :count).by(20)
      end
    end
  end

  describe '.filter_csv_data' do
    it 'filters rows based on valid criteria' do
      csv_data = CSV.read(mock_csv_path, headers: true)
      filtered_data = described_class.filter_csv_data(csv_data)

      expect(filtered_data.size).to eq(20) # Adjust count to match filtered data
      expect(filtered_data.pluck('SYMBOL_NAME')).to include('NIFTY', 'USDINR', 'RELIANCE', 'GOLD')
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
        [nil, nil, 'NSE', 'E', 'EQUITY', 0]
      )
      expect(described_class).not_to be_valid_instrument(invalid_row)
    end
  end

  describe '.valid_buy_sell_indicator?' do
    it 'returns true for rows with valid BUY_SELL_INDICATOR' do
      valid_row = CSV.read(mock_csv_path, headers: true).first
      expect(described_class).to be_valid_buy_sell_indicator(valid_row)
    end

    it 'returns false for rows with invalid BUY_SELL_INDICATOR' do
      invalid_row = CSV::Row.new(
        %w[BUY_SELL_INDICATOR],
        ['B']
      )
      expect(described_class).not_to be_valid_buy_sell_indicator(invalid_row)
    end
  end

  describe '.valid_expiry_date?' do
    it 'returns true for rows with valid or no expiry dates' do
      valid_row = CSV.read(mock_csv_path, headers: true).first
      expect(described_class).to be_valid_expiry_date(valid_row)
    end

    it 'returns false for rows with past expiry dates' do
      invalid_row = CSV::Row.new(
        %w[SM_EXPIRY_DATE],
        ['2023-01-01']
      )
      expect(described_class).not_to be_valid_expiry_date(invalid_row)
    end
  end

  describe '.import_instruments' do
    it 'imports instruments correctly' do
      csv_data = CSV.read(mock_csv_path, headers: true)
      described_class.import_instruments(csv_data)

      expect(Instrument.find_by(symbol_name: 'NIFTY')).to be_present
      expect(Instrument.find_by(symbol_name: 'RELIANCE')).to be_present
      expect(Instrument.find_by(symbol_name: 'USDINR')).to be_present
    end
  end

  describe '.import_derivatives' do
    it 'imports derivatives correctly' do
      csv_data = CSV.read(mock_csv_path, headers: true)
      described_class.import_derivatives(csv_data)

      expect(Derivative.find_by(option_type: 'CE', strike_price: 29_200.0)).to be_present
      expect(Derivative.find_by(option_type: 'PE', strike_price: 83.2)).to be_present
    end
  end

  describe '.import_margin_requirements' do
    it 'imports margin requirements correctly' do
      csv_data = CSV.read(mock_csv_path, headers: true)
      described_class.import_margin_requirements(csv_data)

      instrument = Instrument.find_by(symbol_name: 'RELIANCE')
      expect(MarginRequirement.find_by(instrument: instrument)).to be_present
    end
  end

  describe '.import_order_features' do
    it 'imports order features correctly' do
      csv_data = CSV.read(mock_csv_path, headers: true)
      described_class.import_order_features(csv_data)

      instrument = Instrument.find_by(symbol_name: 'HDFCBANK')
      expect(OrderFeature.find_by(instrument: instrument)).to be_present
    end
  end
end
