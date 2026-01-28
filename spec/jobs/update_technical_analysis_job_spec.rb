require 'rails_helper'

RSpec.describe UpdateTechnicalAnalysisJob do
  describe '#perform' do
    before do
      allow(Market::AnalysisUpdater).to receive(:call)
    end

    it 'calls Market::AnalysisUpdater' do
      described_class.perform_now

      expect(Market::AnalysisUpdater).to have_received(:call)
    end

    it 'runs without errors' do
      expect { described_class.perform_now }.not_to raise_error
    end
  end
end
