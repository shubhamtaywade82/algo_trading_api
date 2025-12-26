require 'rails_helper'

RSpec.describe PaperOneMinuteSignalJob, type: :job do
  describe '#perform' do
    before do
      allow(Market::OneMinutePaperTrader).to receive(:call)
    end

    it 'calls Market::OneMinutePaperTrader' do
      described_class.perform_now
      expect(Market::OneMinutePaperTrader).to have_received(:call)
    end

    it 'runs without errors' do
      expect { described_class.perform_now }.not_to raise_error
    end
  end
end

