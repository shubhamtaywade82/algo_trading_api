# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Orders::Gateway do
  let(:payload) { { security_id: '11536', transaction_type: 'BUY', quantity: 1 } }
  let(:logger) { instance_double(Logger, info: nil, warn: nil) }

  around do |example|
    orig_place_order = ENV.fetch('PLACE_ORDER', nil)
    orig_live_trading = ENV.fetch('LIVE_TRADING', nil)
    example.run
  ensure
    ENV['PLACE_ORDER'] = orig_place_order
    ENV['LIVE_TRADING'] = orig_live_trading
  end

  describe '.place_order_enabled?' do
    it 'is false when PLACE_ORDER is not true' do
      ENV['PLACE_ORDER'] = 'false'
      ENV['LIVE_TRADING'] = 'true'

      expect(described_class.place_order_enabled?(logger: logger)).to be(false)
    end

    # DhanHQ >= 2.7 raises LiveTradingDisabledError from inside the SDK
    # without this, so the gateway has to gate on it too.
    it 'is false when LIVE_TRADING is not true, even with PLACE_ORDER on' do
      ENV['PLACE_ORDER'] = 'true'
      ENV['LIVE_TRADING'] = nil

      expect(described_class.place_order_enabled?(logger: logger)).to be(false)
    end

    it 'is true only when both switches are on' do
      ENV['PLACE_ORDER'] = 'true'
      ENV['LIVE_TRADING'] = 'true'

      expect(described_class.place_order_enabled?(logger: logger)).to be(true)
    end
  end

  describe '.place_order' do
    it 'returns a dry-run result naming PLACE_ORDER when that switch is off' do
      ENV['PLACE_ORDER'] = 'false'
      ENV['LIVE_TRADING'] = 'true'

      result = described_class.place_order(payload, logger: logger)

      expect(result).to include(dry_run: true, blocked: true)
      expect(result[:message]).to match(/PLACE_ORDER/)
    end

    it 'returns a dry-run result naming LIVE_TRADING when only that switch is off' do
      ENV['PLACE_ORDER'] = 'true'
      ENV['LIVE_TRADING'] = 'false'

      result = described_class.place_order(payload, logger: logger)

      expect(result).to include(dry_run: true, blocked: true)
      expect(result[:message]).to match(/LIVE_TRADING/)
    end

    it 'does not touch the broker while blocked' do
      ENV['PLACE_ORDER'] = 'true'
      ENV['LIVE_TRADING'] = 'false'
      order_class = double('OrderClass')
      allow(order_class).to receive(:new)
      stub_const('DhanHQ::Models::Order', order_class)

      described_class.place_order(payload, logger: logger)

      expect(order_class).not_to have_received(:new)
    end

    it 'places through DhanHQ when both switches are on' do
      ENV['PLACE_ORDER'] = 'true'
      ENV['LIVE_TRADING'] = 'true'
      order = double('Order', save: true, order_id: 'OID1', order_status: 'PENDING')
      order_class = double('OrderClass')
      allow(order_class).to receive(:new).with(payload).and_return(order)
      stub_const('DhanHQ::Models::Order', order_class)

      result = described_class.place_order(payload, logger: logger)

      expect(result).to include(dry_run: false, order_id: 'OID1', order_status: 'PENDING')
    end
  end

  describe '.place_super_order' do
    it 'is blocked when LIVE_TRADING is off' do
      ENV['PLACE_ORDER'] = 'true'
      ENV['LIVE_TRADING'] = nil

      result = described_class.place_super_order(payload, logger: logger)

      expect(result).to include(dry_run: true, blocked: true)
      expect(result[:message]).to match(/LIVE_TRADING/)
    end
  end
end
