# frozen_string_literal: true

require 'rails_helper'

# The read side of a paper run has to come from the paper book. Sizing off the
# live balance while filling into the simulator is the worst of both worlds,
# and guards pointed at an empty live book let duplicate entries through and
# never find a position to exit.
RSpec.describe AlertProcessors::Base, type: :service do
  subject(:processor) { described_class.new(alert) }

  let(:instrument) { create(:instrument, segment: 'equity', exchange: 'NSE', security_id: '1333') }
  let(:alert) { create(:alert, instrument_type: 'stock', instrument: instrument) }

  let!(:paper_account) do
    PaperAccount.create!(initial_capital: 1_000_000, available_balance: 400_000,
                         blocked_margin: 150_000, config: PaperAccount::DEFAULT_CONFIG.dup)
  end

  around do |example|
    original = ENV.fetch('PAPER_TRADING', nil)
    ENV['PAPER_TRADING'] = paper_enabled
    example.run
    ENV['PAPER_TRADING'] = original
  end

  context 'when paper trading is enabled' do
    let(:paper_enabled) { 'true' }

    describe '#available_balance' do
      it 'sizes against the simulated book, not the real account' do
        allow(DhanHQ::Models::Funds).to receive(:fetch)

        expect(processor.available_balance).to eq(250_000.0)
        expect(DhanHQ::Models::Funds).not_to have_received(:fetch)
      end
    end

    describe '#dhan_positions' do
      it 'reads the paper book' do
        paper_account.paper_positions.create!(
          security_id: '1333', exchange_segment: 'NSE_EQ', product_type: 'INTRADAY',
          position_type: 'LONG', net_qty: 10, buy_qty: 10, buy_avg: 1_500.0
        )
        allow(DhanHQ::Models::Position).to receive(:all)

        expect(processor.dhan_positions.pluck('securityId')).to eq(['1333'])
        expect(DhanHQ::Models::Position).not_to have_received(:all)
      end
    end
  end

  context 'when paper trading is disabled' do
    let(:paper_enabled) { 'false' }

    it 'reads funds from the broker' do
      # Not an instance_double: the SDK resolves attributes dynamically, so
      # `available_balance` is not a statically defined instance method.
      funds = double('Funds', available_balance: 75_000.0)
      allow(DhanHQ::Models::Funds).to receive(:fetch).and_return(funds)

      expect(processor.available_balance).to eq(75_000.0)
    end

    it 'reads positions from the broker' do
      allow(DhanHQ::Models::Position).to receive(:all).and_return([])

      expect(processor.dhan_positions).to eq([])
      expect(DhanHQ::Models::Position).to have_received(:all)
    end
  end
end
