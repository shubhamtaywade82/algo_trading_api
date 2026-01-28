# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Orders::Adjuster, type: :service do
  let(:position) do
    {
      'securityId' => 'OPT123',
      'tradingSymbol' => 'NIFTY24JUL17500CE',
      'exchangeSegment' => 'NSEFO',
      'netQty' => 75,
      'ltp' => 110,
      'buyAvg' => 100,
      'productType' => 'INTRADAY'
    }
  end

  let(:params) { { trigger_price: 105.5 } }

  context 'when stop loss adjustment is successful' do
    let(:order_list) do
      [{
        'securityId' => 'OPT123',
        'orderId' => 'ORDER123',
        'orderStatus' => 'PENDING',
        'dhanClientId' => 'DUMMY_CLIENT_ID',
        'orderType' => 'LIMIT',
        'quantity' => 75,
        'price' => 110,
        'legName' => '',
        'disclosedQuantity' => 0,
        'validity' => 'DAY'
      }]
    end

    before do
      allow(DhanHQ::Models::Order).to receive(:all).and_return(order_list)
      order_obj = double(
        'DhanHQ::Models::Order',
        modify: true,
        order_status: 'PENDING',
        status: 'PENDING',
        errors: double(full_messages: [])
      )
      allow(DhanHQ::Models::Order).to receive(:find).with('ORDER123').and_return(order_obj)
      stub_request(:post, %r{https://api\.telegram\.org/bot[^/]+/sendMessage}).to_return(status: 200, body: '{}')
    end

    it 'sends an adjustment notification and logs success' do
      expect(TelegramNotifier).to receive(:send_message).with('[Orders::Adjuster] 🔁 Adjusted SL to ₹105.5 for NIFTY24JUL17500CE')
      described_class.call(position, params)
    end
  end

  context 'when stop loss adjustment fails' do
    before do
      order_list = [{
        'securityId' => 'OPT123', 'orderId' => 'ORDER123', 'orderStatus' => 'PENDING',
        'dhanClientId' => 'DUMMY_CLIENT_ID', 'orderType' => 'LIMIT', 'quantity' => 75,
        'price' => 110, 'legName' => '', 'disclosedQuantity' => 0, 'validity' => 'DAY'
      }]
      allow(DhanHQ::Models::Order).to receive(:all).and_return(order_list)
      order_obj = double(
        'DhanHQ::Models::Order',
        modify: true,
        order_status: 'FAILED',
        status: 'FAILED',
        errors: double(full_messages: ['Some error'])
      )
      allow(DhanHQ::Models::Order).to receive(:find).with('ORDER123').and_return(order_obj)
      stub_request(:post, %r{https://api\.telegram\.org/bot[^/]+/sendMessage}).to_return(status: 200, body: '{}')
    end

    it 'triggers fallback exit and sends fallback notification' do
      msg = '[Orders::Adjuster] ⚠️ SL Adjust failed. Fallback exit initiated for NIFTY24JUL17500CE'
      expect(TelegramNotifier).to receive(:send_message).with(msg)
      expect(Orders::Executor).to receive(:call)
        .with(kind_of(Hash), 'FallbackExit', kind_of(Hash))

      described_class.call(position, params)
    end
  end

  context 'when there is no active order to modify' do
    before do
      allow(DhanHQ::Models::Order).to receive(:all).and_return([])
      stub_request(:post, %r{https://api\.telegram\.org/bot[^/]+/sendMessage}).to_return(status: 200, body: '{}')
    end

    it 'triggers fallback exit and sends fallback notification' do
      msg = '[Orders::Adjuster] ⚠️ SL Adjust failed. Fallback exit initiated for NIFTY24JUL17500CE'
      expect(TelegramNotifier).to receive(:send_message).with(msg)
      expect(Orders::Executor).to receive(:call)
        .with(kind_of(Hash), 'FallbackExit', kind_of(Hash))

      described_class.call(position, params)
    end
  end

  context 'when an exception is raised' do
    before do
      allow(DhanHQ::Models::Order).to receive(:all).and_raise(StandardError.new('API Down'))
      stub_request(:post, %r{https://api\.telegram\.org/bot[^/]+/sendMessage}).to_return(status: 200, body: '{}')
    end

    it 'triggers fallback exit and sends fallback notification' do
      msg = '[Orders::Adjuster] ⚠️ SL Adjust failed. Fallback exit initiated for NIFTY24JUL17500CE'
      expect(TelegramNotifier).to receive(:send_message).with(msg)
      expect(Orders::Executor).to receive(:call)
        .with(kind_of(Hash), 'FallbackExit', kind_of(Hash))

      described_class.call(position, params)
    end
  end

  context 'when stop loss adjustment is successful (v2 API)' do
    let(:order_list_v2) do
      [{
        'securityId' => 'OPT123',
        'orderId' => 'ORDER123',
        'orderStatus' => 'PENDING',
        'orderType' => 'LIMIT',
        'quantity' => 75,
        'validity' => 'DAY',
        'price' => 110,
        'dhanClientId' => '1104216308',
        'legName' => nil,
        'disclosedQuantity' => 0
      }]
    end

    before do
      allow(DhanHQ::Models::Order).to receive(:all).and_return(order_list_v2)
      order_obj = double(
        'DhanHQ::Models::Order',
        modify: true,
        order_status: 'PENDING',
        status: 'PENDING',
        errors: double(full_messages: [])
      )
      allow(DhanHQ::Models::Order).to receive(:find).with('ORDER123').and_return(order_obj)
      stub_request(:post, %r{https://api\.telegram\.org/bot[^/]+/sendMessage}).to_return(status: 200, body: '{}')
    end

    it 'sends an adjustment notification and logs success' do
      expect(TelegramNotifier).to receive(:send_message).with('[Orders::Adjuster] 🔁 Adjusted SL to ₹105.5 for NIFTY24JUL17500CE')
      described_class.call(position, params)
    end
  end
end
