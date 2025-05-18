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
    before do
      stub_request(:get, 'https://api.dhan.co/orders')
        .to_return(
          status: 200,
          body: [{
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
          }].to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      stub_request(:put, 'https://api.dhan.co/orders/ORDER123')
        .with(body: hash_including('triggerPrice' => 105.5))
        .to_return(
          status: 200,
          body: { 'orderStatus' => 'PENDING' }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      stub_request(:post, %r{https://api\.telegram\.org/bot[^/]+/sendMessage})
        .to_return(status: 200, body: '{}')
    end

    it 'sends an adjustment notification and logs success' do
      expect(TelegramNotifier).to receive(:send_message).with('🔁 Adjusted SL to ₹105.5 for NIFTY24JUL17500CE')
      described_class.call(position, params)
    end
  end

  context 'when stop loss adjustment fails' do
    before do
      stub_request(:get, 'https://api.dhan.co/orders')
        .to_return(
          status: 200,
          body: [{
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
          }].to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      stub_request(:put, 'https://api.dhan.co/orders/ORDER123')
        .to_return(
          status: 200,
          body: { 'orderStatus' => 'FAILED', 'omsErrorDescription' => 'Some error' }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      stub_request(:post, %r{https://api\.telegram\.org/bot[^/]+/sendMessage}).to_return(status: 200, body: '{}')
    end

    it 'triggers fallback exit and sends fallback notification' do
      expect(TelegramNotifier).to receive(:send_message).with('⚠️ SL Adjust failed. Fallback exit initiated for NIFTY24JUL17500CE')
      expect(Orders::Executor).to receive(:call)
        .with(kind_of(Hash), 'FallbackExit', kind_of(Hash))

      described_class.call(position, params)
    end
  end

  context 'when there is no active order to modify' do
    before do
      stub_request(:get, 'https://api.dhan.co/orders')
        .to_return(
          status: 200,
          body: [].to_json, # empty array = no active orders
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'triggers fallback exit and sends fallback notification' do
      expect(TelegramNotifier).to receive(:send_message).with('⚠️ SL Adjust failed. Fallback exit initiated for NIFTY24JUL17500CE')
      expect(Orders::Executor).to receive(:call)
        .with(kind_of(Hash), 'FallbackExit', kind_of(Hash))

      described_class.call(position, params)
    end
  end

  context 'when an exception is raised' do
    before do
      stub_request(:get, 'https://api.dhan.co/orders').to_raise(StandardError.new('API Down'))
    end

    it 'triggers fallback exit and sends fallback notification' do
      expect(TelegramNotifier).to receive(:send_message).with('⚠️ SL Adjust failed. Fallback exit initiated for NIFTY24JUL17500CE')
      expect(Orders::Executor).to receive(:call)
        .with(kind_of(Hash), 'FallbackExit', kind_of(Hash))

      described_class.call(position, params)
    end
  end

  context 'when stop loss adjustment is successful' do
    before do
      stub_request(:get, 'https://api.dhan.co/orders').to_return(
        status: 200,
        body: [{
          'securityId' => 'OPT123',
          'orderId' => 'ORDER123',
          'orderStatus' => 'PENDING',
          'orderType' => 'LIMIT',
          'quantity' => 75,
          'validity' => 'DAY',
          'price' => 110,
          'dhanClientId' => '1104216308', # dummy value, matches your header
          'legName' => nil,
          'disclosedQuantity' => 0
        }].to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

      stub_request(:put, 'https://api.dhan.co/orders/ORDER123')
        .with(body: hash_including('triggerPrice' => 105.5))
        .to_return(
          status: 200,
          body: { 'status' => 'success', 'orderId' => 'ORDER123', 'orderStatus' => 'PENDING' }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      stub_request(:post, %r{https://api\.telegram\.org/bot[^/]+/sendMessage}).to_return(status: 200, body: '{}')
    end

    it 'sends an adjustment notification and logs success' do
      expect(TelegramNotifier).to receive(:send_message).with('🔁 Adjusted SL to ₹105.5 for NIFTY24JUL17500CE')
      described_class.call(position, params)
    end
  end
end
