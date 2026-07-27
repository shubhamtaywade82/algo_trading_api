# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Paper::FeedSubscriber do
  let(:account) do
    PaperAccount.create!(initial_capital: 1_000_000, available_balance: 1_000_000,
                         config: PaperAccount::DEFAULT_CONFIG.dup)
  end
  let(:hub) { instance_double(Live::MarketFeedHub) }

  before { allow(Live::MarketFeedHub).to receive(:instance).and_return(hub) }

  describe '.follow' do
    it 'subscribes the instrument when the feed is running' do
      allow(hub).to receive_messages(running?: true, subscribe: true)

      expect(described_class.follow(segment: 'NSE_FNO', security_id: '49081')).to be(true)
      expect(hub).to have_received(:subscribe).with(segment: 'NSE_FNO', security_id: '49081')
    end

    # A web process that never started a feed still places paper orders; it
    # must not be dragged into starting one, and must not raise.
    it 'does nothing when no feed is running in this process' do
      allow(hub).to receive(:running?).and_return(false)
      allow(hub).to receive(:subscribe)

      expect(described_class.follow(segment: 'NSE_FNO', security_id: '49081')).to be(false)
      expect(hub).not_to have_received(:subscribe)
    end

    it 'swallows a feed failure rather than failing the placement' do
      allow(hub).to receive(:running?).and_return(true)
      allow(hub).to receive(:subscribe).and_raise(StandardError, 'socket gone')

      expect(described_class.follow(segment: 'NSE_FNO', security_id: '49081')).to be(false)
    end
  end

  describe '.restore_book!' do
    before { allow(hub).to receive_messages(running?: true, subscribe: true) }

    it 'subscribes resting orders and open positions, without duplicates' do
      account.paper_orders.create!(
        security_id: '49081', exchange_segment: 'NSE_FNO', transaction_type: 'BUY',
        order_type: 'LIMIT', product_type: 'MARGIN', quantity: 75, price: 100, status: 'pending'
      )
      account.paper_positions.create!(
        security_id: '49081', exchange_segment: 'NSE_FNO', product_type: 'MARGIN',
        position_type: 'LONG', net_qty: 75
      )
      account.paper_positions.create!(
        security_id: '1333', exchange_segment: 'NSE_EQ', product_type: 'INTRADAY',
        position_type: 'LONG', net_qty: 10
      )

      expect(described_class.restore_book!(account: account)).to eq(2)
      expect(hub).to have_received(:subscribe).with(segment: 'NSE_FNO', security_id: '49081').once
      expect(hub).to have_received(:subscribe).with(segment: 'NSE_EQ', security_id: '1333').once
    end

    it 'ignores orders that are already done and positions that are flat' do
      account.paper_orders.create!(
        security_id: '49081', exchange_segment: 'NSE_FNO', transaction_type: 'BUY',
        order_type: 'MARKET', product_type: 'MARGIN', quantity: 75, status: 'traded'
      )
      account.paper_positions.create!(
        security_id: '1333', exchange_segment: 'NSE_EQ', product_type: 'INTRADAY',
        position_type: 'CLOSED', net_qty: 0
      )

      expect(described_class.restore_book!(account: account)).to eq(0)
    end
  end
end
