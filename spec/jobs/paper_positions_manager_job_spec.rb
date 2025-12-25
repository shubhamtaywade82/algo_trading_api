require 'rails_helper'

RSpec.describe PaperPositionsManagerJob, type: :job do
  describe '#perform' do
    before do
      allow(PaperPositions::Manager).to receive(:call)
    end

    it 'calls PaperPositions::Manager' do
      described_class.perform_now
      expect(PaperPositions::Manager).to have_received(:call)
    end

    it 'runs without errors' do
      expect { described_class.perform_now }.not_to raise_error
    end
  end
end

