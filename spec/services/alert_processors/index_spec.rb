# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AlertProcessors::Index, type: :service do
  let(:alert) { create(:alert, instrument_type: 'index', action: 'buy') }
  let(:processor) { described_class.new(alert) }
  let(:instrument) { create(:instrument, segment: 'index', exchange: 'NSE') }

  before do
    allow(processor).to receive_messages(instrument: instrument, fetch_option_chain: { oc: {} },
                                         select_best_strike: { strike_price: 15_000 }, fetch_instrument_for_strike: instrument)
  end

  describe '#call' do
    context 'when processing is successful' do
      it 'places an order and updates alert status to processed' do
        allow(processor).to receive(:place_order).and_return(true)

        expect { processor.call }.to change { alert.reload.status }.to('processed')
      end
    end

    context 'when an error occurs' do
      it 'raises an error and updates alert status to failed' do
        allow(processor).to receive(:place_order).and_raise('Order placement failed')

        expect { processor.call }.to raise_error('Order placement failed')
        expect(alert.reload.status).to eq('failed')
      end
    end
  end
end
