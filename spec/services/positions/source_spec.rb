# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Positions::Source do
  let!(:account) do
    PaperAccount.create!(initial_capital: 1_000_000, available_balance: 1_000_000,
                         config: PaperAccount::DEFAULT_CONFIG.dup)
  end

  around do |example|
    original = ENV.fetch('PAPER_TRADING', nil)
    ENV['PAPER_TRADING'] = paper_enabled
    example.run
    ENV['PAPER_TRADING'] = original
  end

  def create_position(**attrs)
    account.paper_positions.create!(
      { security_id: '1333', exchange_segment: 'NSE_EQ', product_type: 'INTRADAY',
        position_type: 'LONG', net_qty: 10, buy_qty: 10, buy_avg: 1_400.0 }.merge(attrs)
    )
  end

  # The exit stack reads positions through here. Pointed at the live book during
  # a paper run it manages an empty account: no trailing stop, no risk exit,
  # nothing, while simulated positions run unattended.
  context 'when paper trading is enabled' do
    let(:paper_enabled) { 'true' }

    it 'serves the paper book' do
      create_position
      allow(DhanHQ::Models::Position).to receive(:all)
      rows = described_class.all

      expect(rows.pluck('securityId')).to eq(['1333'])
      expect(DhanHQ::Models::Position).not_to have_received(:all)
    end

    it 'drops flat positions from the open view' do
      create_position(position_type: 'CLOSED', net_qty: 0)

      expect(described_class.open).to be_empty
    end

    # Orders::Analyzer prices P&L off costPrice; without it a paper position
    # analyses as worthless and is skipped by the exit stack.
    it 'carries the entry price the analyzer needs' do
      create_position
      rows = described_class.all

      expect(rows.first['costPrice']).to eq(1_400.0)
    end
  end

  context 'when paper trading is disabled' do
    let(:paper_enabled) { 'false' }

    it 'serves the broker book' do
      allow(DhanHQ::Models::Position).to receive(:all).and_return([])

      expect(described_class.all).to eq([])
      expect(DhanHQ::Models::Position).to have_received(:all)
    end
  end
end
