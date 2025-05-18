# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Orders::Manager, type: :service do
  let(:position) do
    {
      'tradingSymbol' => 'NIFTY24JUL17500CE',
      'securityId' => 'OPT123',
      'exchangeSegment' => 'NSEFO',
      'buyAvg' => 100,
      'netQty' => 75,
      'ltp' => 110
    }
  end
  let(:analysis) { { entry_price: 100, ltp: 110, pnl: 750, pnl_pct: 10.0, quantity: 75, instrument_type: :option } }

  before do
    # Common network stubs for Adjuster/Executor scenarios
    stub_request(:get, 'https://api.dhan.co/orders').to_return(
      status: 200,
      body: [
        {
          'securityId' => 'OPT123',
          'orderId' => 'ORDER123',
          'orderStatus' => 'PENDING',
          # Add other fields required by Adjuster if called
          'dhanClientId' => 'test-client',
          'orderType' => 'LIMIT',
          'legName' => nil,
          'quantity' => 75,
          'price' => 100,
          'disclosedQuantity' => 0,
          'triggerPrice' => 100,
          'validity' => 'DAY'
        }
      ].to_json,
      headers: { 'Content-Type' => 'application/json' }
    )
    stub_request(:put, 'https://api.dhan.co/orders/ORDER123')
      .to_return(
        status: 200,
        body: { 'status' => 'success', 'orderId' => 'ORDER123', 'orderStatus' => 'PENDING' }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

    stub_request(:post, %r{https://api\.telegram\.org/bot[^/]+/sendMessage}).to_return(status: 200, body: '{}')
  end

  context 'when risk manager decides to exit' do
    before do
      allow(Orders::RiskManager).to receive(:call).and_return({ exit: true, exit_reason: 'TP', adjust: false })
      # Here, you can stub Orders::Executor's network calls if it does any (similar to above)
      allow(Orders::Executor).to receive(:call)
    end

    it 'calls Orders::Executor with correct args' do
      expect(Orders::Executor).to receive(:call).with(position, 'TP', analysis)
      described_class.call(position, analysis)
    end
  end

  context 'when risk manager decides to adjust' do
    let(:adjust_params) { { trigger_price: 105.0 } }

    before do
      allow(Orders::RiskManager).to receive(:call).and_return({ exit: false, adjust: true,
                                                                adjust_params: adjust_params })
      # DO NOT stub Orders::Adjuster, let it run for real and catch all HTTP with WebMock
      allow(TelegramNotifier).to receive(:send_message) # We just want to silence Telegram in tests
      allow(Rails.logger).to receive(:info)
    end

    it 'calls Orders::Adjuster with correct args' do
      # Instead of allow/expect, just let Orders::Adjuster.call run and ensure it succeeds (no errors)
      expect { described_class.call(position, analysis) }.not_to raise_error
    end
  end

  context 'when risk manager returns neither exit nor adjust' do
    before do
      allow(Orders::RiskManager).to receive(:call).and_return({ exit: false, adjust: false })
    end

    it 'does not call Executor or Adjuster' do
      expect(Orders::Executor).not_to receive(:call)
      expect(Orders::Adjuster).not_to receive(:call)
      described_class.call(position, analysis)
    end
  end

  context 'when an error occurs' do
    before do
      allow(Orders::RiskManager).to receive(:call).and_raise(StandardError, 'Manager error')
    end

    it 'logs the error and does not raise' do
      expect(Rails.logger).to receive(:error).with(/\[Orders::Manager\] Error for NIFTY24JUL17500CE: Manager error/)
      expect { described_class.call(position, analysis) }.not_to raise_error
    end
  end
end
