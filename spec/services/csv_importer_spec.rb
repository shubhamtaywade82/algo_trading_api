require 'rails_helper'

RSpec.describe CsvImporter, type: :class do
  let(:sample_csv_path) { Rails.root.join('spec', 'fixtures', 'sample_csv.csv') }

  before do
    # Mock the download_csv method to return the path to the sample CSV file
    allow(CsvImporter).to receive(:download_csv).and_return(sample_csv_path)
  end

  describe '.import' do
    it 'imports all data successfully' do
      expect { CsvImporter.import }.to change { Instrument.count }.by(5)
                                     .and change { Derivative.count }.by(2)
                                     .and change { MarginRequirement.count }.by(5)
                                     .and change { OrderFeature.count }.by(5)
    end
  end
end