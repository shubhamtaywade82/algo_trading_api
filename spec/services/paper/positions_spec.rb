# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Paper::Positions do
  def paper_fill(side:, qty:, price:, security_id: '49081')
    Order.create!(
      dhan_order_id: "PAPER-#{SecureRandom.hex(4)}",
      transaction_type: side,
      product_type: 'INTRADAY',
      order_type: 'MARKET',
      validity: 'DAY',
      exchange_segment: 'NSE_FNO',
      security_id: security_id,
      quantity: qty,
      filled_qty: qty,
      average_traded_price: price,
      ltp: price,
      order_status: 'TRADED'
    )
  end

  before do
    Live::TickCache.clear!
    allow(Charges::Calculator).to receive(:call).and_return(20.0)
  end

  after { Live::TickCache.clear! }

  describe '.open' do
    it 'nets buys against sells' do
      paper_fill(side: 'BUY', qty: 100, price: 50.0)
      paper_fill(side: 'SELL', qty: 40, price: 55.0)

      position = described_class.open.first

      expect(position[:net_qty]).to eq(60)
      expect(position[:buy_avg]).to eq(50.0)
      expect(position[:sell_avg]).to eq(55.0)
    end

    it 'weights the entry across multiple fills' do
      paper_fill(side: 'BUY', qty: 50, price: 100.0)
      paper_fill(side: 'BUY', qty: 50, price: 200.0)

      expect(described_class.open.first[:buy_avg]).to eq(150.0)
    end

    it 'excludes a flat position' do
      paper_fill(side: 'BUY', qty: 50, price: 100.0)
      paper_fill(side: 'SELL', qty: 50, price: 110.0)

      expect(described_class.open).to be_empty
    end

    it 'separates instruments' do
      paper_fill(side: 'BUY', qty: 10, price: 100.0, security_id: '1')
      paper_fill(side: 'BUY', qty: 20, price: 200.0, security_id: '2')

      expect(described_class.open.pluck(:security_id)).to contain_exactly('1', '2')
    end

    it 'ignores live orders' do
      paper_fill(side: 'BUY', qty: 10, price: 100.0)
      Order.create!(
        dhan_order_id: 'LIVE-123', transaction_type: 'BUY', product_type: 'INTRADAY',
        order_type: 'MARKET', validity: 'DAY', exchange_segment: 'NSE_FNO',
        security_id: '99999', quantity: 5, filled_qty: 5,
        average_traded_price: 10.0, order_status: 'TRADED'
      )

      expect(described_class.open.pluck(:security_id)).to eq(['49081'])
    end
  end

  describe 'P&L' do
    it 'realises profit on the matched quantity only' do
      paper_fill(side: 'BUY', qty: 100, price: 50.0)
      paper_fill(side: 'SELL', qty: 40, price: 55.0)

      # 40 matched x (55 - 50) = 200
      expect(described_class.open.first[:realized_pnl]).to eq(200.0)
    end

    it 'marks the open leg against the live feed' do
      paper_fill(side: 'BUY', qty: 100, price: 50.0)
      Live::TickCache.put('NSE_FNO', '49081', ltp: 60.0)

      position = described_class.open.first

      expect(position[:ltp]).to eq(60.0)
      expect(position[:unrealized_pnl]).to eq(1_000.0) # 100 x (60 - 50)
    end

    it 'runs unrealised the other way for a short' do
      paper_fill(side: 'SELL', qty: 50, price: 100.0)
      Live::TickCache.put('NSE_FNO', '49081', ltp: 90.0)

      # Short 50 from 100, now 90: (90 - 100) * -50 = +500
      expect(described_class.open.first[:unrealized_pnl]).to eq(500.0)
    end

    # A paper P&L that ignored brokerage and STT would flatter every strategy.
    it 'applies real Dhan charges' do
      paper_fill(side: 'BUY', qty: 100, price: 50.0)

      expect(described_class.open.first[:charges]).to eq(20.0)
      expect(Charges::Calculator).to have_received(:call).at_least(:once)
    end
  end

  describe '.summary' do
    it 'nets realised, unrealised and charges across the book' do
      paper_fill(side: 'BUY', qty: 100, price: 50.0)
      paper_fill(side: 'SELL', qty: 100, price: 60.0)

      summary = described_class.summary

      expect(summary[:realized_pnl]).to eq(1_000.0)
      expect(summary[:open_positions]).to eq(0)
      expect(summary[:net_pnl]).to eq(1_000.0 - summary[:charges])
    end
  end

  describe '.reset!' do
    it 'clears paper fills but leaves live orders alone' do
      paper_fill(side: 'BUY', qty: 10, price: 100.0)
      Order.create!(
        dhan_order_id: 'LIVE-1', transaction_type: 'BUY', product_type: 'INTRADAY',
        order_type: 'MARKET', validity: 'DAY', exchange_segment: 'NSE_FNO',
        security_id: '1', quantity: 1, filled_qty: 1,
        average_traded_price: 1.0, order_status: 'TRADED'
      )

      described_class.reset!

      expect(Order.pluck(:dhan_order_id)).to eq(['LIVE-1'])
    end
  end
end
