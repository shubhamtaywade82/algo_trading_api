# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Paper::Broker do
  let(:base_payload) do
    {
      security_id: '49081',
      exchange_segment: 'NSE_FNO',
      transaction_type: 'BUY',
      order_type: 'MARKET',
      quantity: 50,
      product_type: 'INTRADAY'
    }
  end

  around do |example|
    original = ENV.to_h.slice('PAPER_TRADING', 'PAPER_SLIPPAGE_PCT')
    example.run
  ensure
    %w[PAPER_TRADING PAPER_SLIPPAGE_PCT].each { |k| ENV[k] = original[k] }
  end

  before do
    Live::TickCache.clear!
    Live::TickCache.put('NSE_FNO', '49081', ltp: 100.0)
  end

  after { Live::TickCache.clear! }

  describe '.enabled?' do
    it 'follows PAPER_TRADING' do
      ENV['PAPER_TRADING'] = 'true'
      expect(described_class).to be_enabled

      ENV['PAPER_TRADING'] = 'false'
      expect(described_class).not_to be_enabled
    end
  end

  describe 'market fills' do
    it 'fills a buy above the mark, moving slippage against the taker' do
      ENV['PAPER_SLIPPAGE_PCT'] = '1.0'

      result = described_class.place(base_payload)

      expect(result).to include(paper: true, order_status: 'TRADED', filled_qty: 50)
      expect(result[:average_traded_price]).to eq(101.0)
    end

    it 'fills a sell below the mark' do
      ENV['PAPER_SLIPPAGE_PCT'] = '1.0'

      result = described_class.place(base_payload.merge(transaction_type: 'SELL'))

      expect(result[:average_traded_price]).to eq(99.0)
    end

    it 'persists the fill as a paper Order row' do
      expect { described_class.place(base_payload) }.to change(Order, :count).by(1)

      order = Order.last
      expect(order.dhan_order_id).to start_with('PAPER-')
      # Order#order_status is an enum, so it reads back as the key.
      expect(order.order_status).to eq('traded')
      expect(order.filled_qty).to eq(50)
    end
  end

  describe 'limit orders' do
    it 'fills a marketable buy limit without market slippage' do
      result = described_class.place(base_payload.merge(order_type: 'LIMIT', price: 105.0))

      # Limit is through the market, so it fills at the better price.
      expect(result[:average_traded_price]).to eq(100.0)
      expect(result[:order_status]).to eq('TRADED')
    end

    # A non-marketable limit resting is a real outcome, not an error.
    it 'rests a buy limit below the market instead of filling' do
      result = described_class.place(base_payload.merge(order_type: 'LIMIT', price: 95.0))

      expect(result[:order_status]).to eq('PENDING')
      expect(result[:filled_qty]).to eq(0)
      expect(result[:message]).to match(/not marketable/)
    end

    it 'rests a sell limit above the market' do
      result = described_class.place(
        base_payload.merge(transaction_type: 'SELL', order_type: 'LIMIT', price: 105.0)
      )

      expect(result[:order_status]).to eq('PENDING')
    end

    it 'does not persist a resting order as a fill' do
      expect do
        described_class.place(base_payload.merge(order_type: 'LIMIT', price: 95.0))
      end.not_to change(Order, :count)
    end
  end

  describe 'pricing sources' do
    it 'prefers the websocket tick over REST' do
      allow(Instrument).to receive(:find_by)

      described_class.place(base_payload)

      expect(Instrument).not_to have_received(:find_by)
    end

    it 'falls back to REST when no tick is cached' do
      Live::TickCache.clear!
      instrument = instance_double(Instrument, ltp: 200.0)
      allow(Instrument).to receive(:find_by).and_return(instrument)

      result = described_class.place(base_payload)

      expect(result[:average_traded_price]).to be_within(0.5).of(200.0)
    end

    it 'reports an error when no price can be established' do
      Live::TickCache.clear!
      allow(Instrument).to receive(:find_by).and_return(nil)

      result = described_class.place(base_payload.except(:price))

      expect(result).to include(paper: true, error: true)
      expect(result[:message]).to match(/no reference price/)
    end
  end

  describe 'routing through Orders::Gateway' do
    it 'intercepts placement when paper trading is on' do
      ENV['PAPER_TRADING'] = 'true'
      order_class = double('OrderClass')
      allow(order_class).to receive(:new)
      stub_const('DhanHQ::Models::Order', order_class)

      result = Orders::Gateway.place_order(base_payload)

      expect(result).to include(paper: true, order_status: 'TRADED')
      expect(order_class).not_to have_received(:new)
    end

    it 'leaves the live path untouched when paper trading is off' do
      ENV['PAPER_TRADING'] = 'false'

      result = Orders::Gateway.place_order(base_payload, logger: nil)

      expect(result[:paper]).to be_nil
      expect(result).to include(dry_run: true, blocked: true)
    end
  end
end
