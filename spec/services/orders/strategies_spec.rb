# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Orders::Strategies::BaseStrategy, type: :service do
  let(:alert) { create(:alert, instrument_type: 'stock') }
  let(:strategy) { described_class.new(alert) }

  describe '#execute' do
    it 'raises NotImplementedError when not overridden' do
      expect { strategy.execute }.to raise_error(NotImplementedError)
    end
  end
end

RSpec.describe Orders::Strategies::IntradayStockStrategy, type: :service do
  let(:alert) { create(:alert, instrument_type: 'stock', strategy_type: 'intraday') }
  let(:strategy) { described_class.new(alert) }

  describe '#execute' do
    it 'places an intraday order' do
      allow(strategy).to receive(:place_order).and_return(true)

      expect { strategy.execute }.not_to raise_error
    end
  end
end

RSpec.describe Orders::Strategies::SwingStockStrategy, type: :service do
  let(:alert) { create(:alert, instrument_type: 'stock', strategy_type: 'swing') }
  let(:strategy) { described_class.new(alert) }

  describe '#execute' do
    it 'places a swing order' do
      allow(strategy).to receive(:place_order).and_return(true)

      expect { strategy.execute }.not_to raise_error
    end
  end
end
