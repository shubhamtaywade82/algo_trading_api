# frozen_string_literal: true

require 'rails_helper'

# Covers the multi-asset routing added for DhanHQ 3.2.x: the Global Stocks
# (USD) book, basket orders, and the SDK failure modes the gateway now
# translates instead of letting escape.
RSpec.describe Orders::Gateway do
  let(:logger) { instance_double(Logger, info: nil, warn: nil, error: nil) }

  around do |example|
    orig_place_order = ENV.fetch('PLACE_ORDER', nil)
    orig_live_trading = ENV.fetch('LIVE_TRADING', nil)
    ENV['PLACE_ORDER'] = 'true'
    ENV['LIVE_TRADING'] = 'true'
    example.run
  ensure
    ENV['PLACE_ORDER'] = orig_place_order
    ENV['LIVE_TRADING'] = orig_live_trading
  end

  describe '.infer_asset_class' do
    it 'routes the US segment to the global book' do
      expect(described_class.infer_asset_class(exchange_segment: 'INX_EQ', security_id: 'AAPL')).to eq(:global)
    end

    it 'treats a non-numeric security id with no segment as a US ticker' do
      expect(described_class.infer_asset_class(security_id: 'TSLA')).to eq(:global)
    end

    it 'keeps numeric security ids domestic' do
      expect(described_class.infer_asset_class(exchange_segment: 'NSE_EQ', security_id: '11536')).to eq(:equity)
    end

    it 'classifies each domestic segment' do
      expect(described_class.infer_asset_class(exchange_segment: 'NSE_FNO', security_id: '49081')).to eq(:futures)
      expect(described_class.infer_asset_class(exchange_segment: 'IDX_I', security_id: '13')).to eq(:index)
      expect(described_class.infer_asset_class(exchange_segment: 'MCX_COMM', security_id: '114')).to eq(:commodity)
    end
  end

  describe '.place_global_order' do
    let(:payload) do
      { security_id: 'AAPL', transaction_type: 'BUY', order_type: 'LIMIT', quantity: 2, price: 180.0 }
    end

    it 'places through the GlobalStocks book and reports it' do
      order = double('GSOrder', order_id: 'GS-1', order_status: 'PENDING')
      gs_order = double('GSOrderClass')
      allow(gs_order).to receive(:place).and_return(order)
      stub_const('DhanHQ::Models::GlobalStocks::Order', gs_order)

      result = described_class.place_global_order(payload, logger: logger)

      expect(result).to include(dry_run: false, book: :global, order_id: 'GS-1')
    end

    it 'drops domestic-only fields and floats the quantity' do
      gs_order = double('GSOrderClass')
      allow(gs_order).to receive(:place).and_return(double('o', order_id: 'x', order_status: 'PENDING'))
      stub_const('DhanHQ::Models::GlobalStocks::Order', gs_order)

      described_class.place_global_order(
        payload.merge(exchange_segment: 'NSE_EQ', product_type: 'INTRADAY', validity: 'DAY'), logger: logger
      )

      expect(gs_order).to have_received(:place) do |sent|
        expect(sent).not_to include(:exchange_segment, :product_type, :validity)
        # Fractional shares: the Integer must be coerced, not just == 2.
        expect(sent[:quantity]).to be_a(Float).and eq(2.0)
      end
    end

    it 'is blocked by the same switches as a domestic order' do
      ENV['LIVE_TRADING'] = 'false'

      result = described_class.place_global_order(payload, logger: logger)

      expect(result).to include(dry_run: true, blocked: true)
    end
  end

  describe '.place routing' do
    it 'sends a US ticker to the global book' do
      allow(described_class).to receive(:place_global_order).and_return(book: :global)

      described_class.place({ security_id: 'AAPL' }, logger: logger)

      expect(described_class).to have_received(:place_global_order)
    end

    it 'sends a numeric domestic payload to the regular book' do
      allow(described_class).to receive(:place_order).and_return(book: :domestic)

      described_class.place({ exchange_segment: 'NSE_EQ', security_id: '11536' }, logger: logger)

      expect(described_class).to have_received(:place_order)
    end
  end

  describe '.place_basket_order' do
    let(:legs) do
      [
        { sequence: 1, security_id: '49081', transaction_type: 'BUY', quantity: 50 },
        { sequence: 2, security_id: '49082', transaction_type: 'SELL', quantity: 50 }
      ]
    end

    it 'reports partial acceptance rather than a single order id' do
      multi = double('MultiOrder', order_ids: %w[A1], accepted: [legs.first], rejected: [legs.last],
                                   all_accepted?: false)
      multi_class = double('MultiOrderClass')
      allow(multi_class).to receive(:create).with(legs).and_return(multi)
      stub_const('DhanHQ::Models::MultiOrder', multi_class)

      result = described_class.place_basket_order(legs, logger: logger)

      expect(result).to include(book: :basket, order_ids: %w[A1], all_accepted: false)
      expect(result[:rejected].size).to eq(1)
    end
  end

  describe 'SDK failure modes' do
    let(:payload) { { security_id: '11536', correlation_id: 'abc-123' } }

    def stub_order_raising(error)
      order = double('Order')
      allow(order).to receive(:save).and_raise(error)
      order_class = double('OrderClass')
      allow(order_class).to receive(:new).and_return(order)
      stub_const('DhanHQ::Models::Order', order_class)
    end

    it 'translates a risk-pipeline rejection into a blocked result' do
      stub_order_raising(DhanHQ::RiskViolation.new('daily loss limit breached'))

      result = described_class.place_order(payload, logger: logger)

      expect(result).to include(blocked: true, risk_violation: true)
      expect(result[:message]).to match(/daily loss/)
    end

    # The SDK stopped retrying writes in 3.2 because the order may already be
    # live; the gateway must surface that for reconciliation, never retry.
    it 'marks a transient write failure reconcilable and keeps the correlation id' do
      stub_order_raising(DhanHQ::NetworkError.new('execution expired'))

      result = described_class.place_order(payload, logger: logger)

      expect(result).to include(error: true, reconcilable: true, correlation_id: 'abc-123')
    end

    it 'does not resubmit after a transient write failure' do
      order = double('Order')
      allow(order).to receive(:save).and_raise(DhanHQ::NetworkError.new('timeout'))
      order_class = double('OrderClass')
      allow(order_class).to receive(:new).and_return(order)
      stub_const('DhanHQ::Models::Order', order_class)

      described_class.place_order(payload, logger: logger)

      expect(order).to have_received(:save).once
    end

    it 'reports a contract rejection as an error, not a block' do
      stub_order_raising(DhanHQ::ValidationError.new('Invalid parameters'))

      result = described_class.place_order(payload, logger: logger)

      expect(result).to include(error: true)
      expect(result[:blocked]).to be_nil
    end
  end
end
