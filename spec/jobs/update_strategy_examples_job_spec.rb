require 'rails_helper'

RSpec.describe UpdateStrategyExamplesJob do
  describe '#perform' do
    let(:option_chain) { { 'calls' => [], 'puts' => [] } }
    let(:params) { { symbol: 'NIFTY', expiry: '2024-01-25' } }

    before do
      allow(Option::StrategyExampleUpdater).to receive(:update_examples)
    end

    it 'calls Option::StrategyExampleUpdater with correct parameters' do
      described_class.perform_now(option_chain, params)

      expect(Option::StrategyExampleUpdater).to have_received(:update_examples).with(option_chain, params)
    end

    it 'runs without errors' do
      expect { described_class.perform_now(option_chain, params) }.not_to raise_error
    end

    context 'when update_examples raises an error' do
      before do
        allow(Option::StrategyExampleUpdater).to receive(:update_examples).and_raise(StandardError, 'Update failed')
      end

      it 'raises the error' do
        expect { described_class.perform_now(option_chain, params) }.to raise_error(StandardError, 'Update failed')
      end
    end
  end
end
