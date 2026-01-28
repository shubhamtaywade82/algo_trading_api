# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InstrumentsImporter, type: :service do
  include CsvMockHelper

  let(:mock_csv_path) { CsvMockHelper::MOCK_CSV_PATH }

  before { generate_mock_csv }

  describe '.import' do
    context 'when file_path is provided' do
      it 'imports instruments and derivatives from the CSV file' do
        expect { described_class.import(mock_csv_path) }.to change(Instrument, :count)
        expect(Instrument.find_by(symbol_name: 'NIFTY')).to be_present
        expect(Instrument.find_by(symbol_name: 'USDINR')).to be_present
        expect(Instrument.find_by(symbol_name: 'GOLD')).to be_present
      end

      it 'returns a summary hash' do
        summary = described_class.import(mock_csv_path)
        expect(summary).to include(:instrument_rows, :derivative_rows, :instrument_upserts, :derivative_upserts, :instrument_total,
                                   :derivative_total)
      end
    end

    context 'when file_path is not provided' do
      before do
        allow(described_class).to receive(:fetch_csv_with_cache).and_return(File.read(mock_csv_path))
      end

      it 'uses cached/fetched CSV and imports' do
        expect(described_class).to receive(:fetch_csv_with_cache)
        expect { described_class.import }.to change(Instrument, :count)
      end
    end
  end

  describe '.import_from_csv' do
    it 'imports instruments then derivatives from CSV string' do
      csv_content = File.read(mock_csv_path)
      summary = described_class.import_from_csv(csv_content)

      expect(summary[:instrument_total]).to eq(Instrument.count)
      expect(summary[:derivative_total]).to eq(Derivative.count)
      expect(Instrument.find_by(symbol_name: 'NIFTY')).to be_present
      expect(Derivative.count).to be >= 0
    end
  end
end
