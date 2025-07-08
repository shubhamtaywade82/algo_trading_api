# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AlertProcessorFactory, type: :service do
  let!(:instrument) { create(:instrument) } # Ensure the instrument exists for associated alerts

  describe '.build' do
    context 'when instrument type is stock' do
      let(:stock_alert) { build(:alert, instrument_type: 'stock', instrument_id: instrument.id) }

      it 'returns a Stock processor' do
        processor = described_class.build(stock_alert)
        expect(processor).to be_a(AlertProcessors::Stock)
      end
    end

    context 'when instrument type is index' do
      let(:index_alert) { build(:alert, instrument_type: 'index', instrument_id: create(:instrument, :nifty).id) }

      it 'returns an Index processor' do
        processor = described_class.build(index_alert)
        expect(processor).to be_a(AlertProcessors::Index)
      end
    end

    context 'when instrument type is unsupported' do
      let(:unsupported_alert) { build(:alert, instrument_type: 'commodity', instrument: instrument) }

      it 'raises a NotImplementedError' do
        expect do
          described_class.build(unsupported_alert)
        end.to raise_error(NotImplementedError, /Unsupported instrument type/)
      end
    end
  end
end
