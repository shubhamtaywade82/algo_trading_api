require 'rails_helper'

RSpec.describe CsvImportJob, type: :job do
  describe '#perform' do
    let(:file_url) { 'https://example.com/instruments.csv' }
    let(:file_path) { Rails.root.join('tmp/api-scrip-master-detailed.csv') }
    let(:file_content) { "symbol,name,exchange\nRELIANCE,Reliance Industries,NSE" }

    before do
      allow(ENV).to receive(:fetch).with('CSV_FILE_URL', nil).and_return(file_url)
      allow(URI).to receive(:open).with(file_url).and_return(StringIO.new(file_content))
      allow(InstrumentsImporter).to receive(:import)
      allow(FileUtils).to receive(:rm_f)
    end

    it 'downloads file from URL' do
      expect(File).to receive(:write).with(file_path, file_content)

      described_class.perform_now
    end

    it 'calls InstrumentsImporter with file path' do
      described_class.perform_now

      expect(InstrumentsImporter).to have_received(:import).with(file_path)
    end

    it 'cleans up file after import' do
      described_class.perform_now

      expect(FileUtils).to have_received(:rm_f).with(file_path)
    end

    it 'runs without errors' do
      expect { described_class.perform_now }.not_to raise_error
    end

    context 'when file download fails' do
      before do
        allow(URI).to receive(:open).and_raise(StandardError, 'Download failed')
      end

      it 'raises the error' do
        expect { described_class.perform_now }.to raise_error(StandardError, 'Download failed')
      end
    end

    context 'when import fails' do
      before do
        allow(InstrumentsImporter).to receive(:import).and_raise(StandardError, 'Import failed')
      end

      it 'raises the error' do
        expect { described_class.perform_now }.to raise_error(StandardError, 'Import failed')
      end
    end
  end
end
