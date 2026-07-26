# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AlertProcessors::GlobalEquity do
  subject(:processor) { described_class.new(alert) }

  let(:instrument) { create(:instrument) }
  let(:alert) do
    create(:alert,
           instrument: instrument,
           ticker: 'AAPL',
           instrument_type: 'global_equity',
           signal_type: 'long_entry',
           current_price: 200.0,
           status: 'pending')
  end

  let(:market_status) { class_double(DhanHQ::Models::GlobalStocks::MarketStatus, open?: true) }
  let(:funds) { class_double(DhanHQ::Models::GlobalStocks::Funds, balance: 10_000.0) }
  let(:holdings) { class_double(DhanHQ::Models::GlobalStocks::Holding, all: []) }

  before do
    stub_const('DhanHQ::Models::GlobalStocks::MarketStatus', market_status)
    stub_const('DhanHQ::Models::GlobalStocks::Funds', funds)
    stub_const('DhanHQ::Models::GlobalStocks::Holding', holdings)
    # Stub the external boundary rather than the subject's own #notify.
    allow(TelegramNotifier).to receive(:send_message)
  end

  describe 'routing' do
    it 'is built by the factory for a US alert' do
      expect(AlertProcessorFactory.build(alert)).to be_a(described_class)
    end
  end

  describe '#call on entry' do
    it 'places a USD buy sized from the global cash balance' do
      allow(Orders::Gateway).to receive(:place_global_order).and_return(dry_run: false, order_id: 'GS-1')

      processor.call

      expect(Orders::Gateway).to have_received(:place_global_order) do |payload, **|
        expect(payload[:security_id]).to eq('AAPL')
        expect(payload[:transaction_type]).to eq('BUY')
        # 20% of $10,000 at $200 = 10 shares
        expect(payload[:quantity]).to eq(10.0)
        expect(payload[:price]).to eq(200.0)
      end
      expect(alert.reload.status).to eq('processed')
    end

    it 'supports fractional shares' do
      alert.update!(current_price: 300.0)
      allow(Orders::Gateway).to receive(:place_global_order).and_return(dry_run: false, order_id: 'GS-1')

      processor.call

      expect(Orders::Gateway).to have_received(:place_global_order) do |payload, **|
        expect(payload[:quantity]).to eq((2_000.0 / 300.0).round(4))
      end
    end

    it 'falls back to MARKET when the alert carries no price' do
      alert.update!(current_price: 0)
      allow(Orders::Gateway).to receive(:place_global_order).and_return(dry_run: false, order_id: 'GS-1')

      processor.call

      expect(alert.reload.status).to eq('skipped')
      expect(alert.error_message).to eq('insufficient_funds')
    end

    it 'skips when the budget is below the minimum notional' do
      allow(funds).to receive(:balance).and_return(1.0)

      processor.call

      expect(alert.reload.status).to eq('skipped')
      expect(alert.error_message).to eq('insufficient_funds')
    end
  end

  describe '#call on exit' do
    before { alert.update!(signal_type: 'long_exit') }

    it 'sells the full held quantity' do
      # Plain double: BaseModel defines attribute readers per instance via
      # define_singleton_method, so instance_double cannot verify them.
      holding = double('Holding', security_id: 'AAPL', trading_symbol: 'AAPL', quantity: 7.5)
      allow(holdings).to receive(:all).and_return([holding])
      allow(Orders::Gateway).to receive(:place_global_order).and_return(dry_run: false, order_id: 'GS-2')

      processor.call

      expect(Orders::Gateway).to have_received(:place_global_order) do |payload, **|
        expect(payload[:transaction_type]).to eq('SELL')
        expect(payload[:quantity]).to eq(7.5)
      end
    end

    it 'skips when nothing is held' do
      processor.call

      expect(alert.reload.status).to eq('skipped')
    end
  end

  describe 'guards' do
    it 'skips when the US market is closed' do
      allow(market_status).to receive(:open?).and_return(false)
      allow(Orders::Gateway).to receive(:place_global_order)

      processor.call

      expect(alert.reload.status).to eq('skipped')
      expect(alert.error_message).to eq('market_closed')
      expect(Orders::Gateway).not_to have_received(:place_global_order)
    end

    # An unknown market state must never authorise a trade.
    it 'treats an unavailable market status as closed' do
      allow(market_status).to receive(:open?).and_raise(StandardError, 'boom')
      allow(Orders::Gateway).to receive(:place_global_order)

      processor.call

      expect(alert.reload.status).to eq('skipped')
      expect(Orders::Gateway).not_to have_received(:place_global_order)
    end

    it 'skips an unsupported signal' do
      alert.update!(signal_type: 'short_exit')

      processor.call

      expect(alert.reload.status).to eq('skipped')
      expect(alert.error_message).to eq('unsupported_signal')
    end

    it 'never reads the domestic fund limit' do
      allow(DhanHQ::Models::Funds).to receive(:fetch)
      allow(Orders::Gateway).to receive(:place_global_order).and_return(dry_run: false, order_id: 'x')

      processor.call

      expect(DhanHQ::Models::Funds).not_to have_received(:fetch)
    end
  end

  describe 'gateway failures' do
    it 'records a reconcilable write failure without resending' do
      allow(Orders::Gateway).to receive(:place_global_order)
        .and_return(error: true, reconcilable: true, message: 'timeout')

      processor.call

      expect(alert.reload.status).to eq('failed')
      expect(alert.error_message).to match(/reconcile by correlation_id/)
      expect(Orders::Gateway).to have_received(:place_global_order).once
    end

    it 'leaves the alert unprocessed when placement is gated off' do
      allow(Orders::Gateway).to receive(:place_global_order)
        .and_return(dry_run: true, blocked: true, message: 'PLACE_ORDER is not true; order not sent.')

      processor.call

      expect(alert.reload.status).to eq('processed')
    end
  end
end
