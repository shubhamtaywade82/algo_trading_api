# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AlertProcessors::Stock, type: :service do
  let(:alert) { create(:alert, instrument_type: 'stock', strategy_type: 'intraday') }
  let(:processor) { described_class.new(alert) }

  describe '#call' do
    context 'when strategy is valid' do
      before do
        allow(Orders::Strategies::IntradayStockStrategy).to receive(:new).and_return(double(execute: true))
      end

      it 'executes the strategy and updates alert status to processed' do
        expect { processor.call }.to change { alert.reload.status }.to('processed')
      end
    end

    context 'when strategy is invalid' do
      before do
        alert.update!(strategy_type: 'unsupported')
      end

      it 'raises an error and updates alert status to failed' do
        expect { processor.call }.to raise_error(RuntimeError, /Unsupported strategy type/)
        expect(alert.reload.status).to eq('failed')
      end
    end
  end
end
