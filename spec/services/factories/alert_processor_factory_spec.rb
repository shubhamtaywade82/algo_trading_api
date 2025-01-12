# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AlertProcessorFactory, type: :factory do
  describe '.build' do
    let(:stock_alert) { build(:alert, instrument_type: 'stock') }
    let(:index_alert) { build(:alert, instrument_type: 'index') }

    it 'returns a Stock processor for stock alerts' do
      processor = described_class.build(stock_alert)
      expect(processor).to be_a(AlertProcessors::Stock)
    end

    it 'returns an Index processor for index alerts' do
      processor = described_class.build(index_alert)
      expect(processor).to be_a(AlertProcessors::Index)
    end

    it 'raises an error for unsupported instrument types' do
      unsupported_alert = build(:alert, instrument_type: 'unsupported')
      expect { described_class.build(unsupported_alert) }.to raise_error(NotImplementedError)
    end
  end
end
