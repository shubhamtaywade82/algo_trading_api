# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Orders::Manager, type: :service do
  let(:base_position) do
    {
      'tradingSymbol' => 'NIFTY24JUL17500CE',
      'securityId' => 'OPT123',
      'exchangeSegment' => 'NSE_FNO',
      'buyAvg' => 100,
      'netQty' => 75,
      'ltp' => 110,
      'productType' => 'INTRADAY'
    }
  end

  let(:base_analysis) do
    {
      entry_price: 100,
      ltp: 110,
      pnl: 750,
      pnl_pct: 10.0,
      quantity: 75,
      instrument_type: :option
    }
  end

  before do
    stub_request(:get, 'https://api.dhan.co/orders').to_return(
      status: 200,
      body: [
        {
          'securityId' => 'OPT123',
          'orderId' => 'ORDER123',
          'orderStatus' => 'PENDING',
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

  context 'when risk manager decides to exit (TP hit)' do
    let(:position) { base_position.merge('ltp' => 161) }
    let(:analysis) do
      base_analysis.merge(
        ltp: 161,
        pnl: (161 - 100) * 75,
        pnl_pct: ((161 - 100) * 75.0 / (100 * 75.0) * 100).round(2),
        quantity: 75
      )
    end

    it 'calls Orders::Executor with TakeProfit_Net reason using net pnl with charges' do
      expect(Orders::Executor).to receive(:call).with(
        position,
        a_string_matching(/^TakeProfit_Net_/),
        analysis
      )
      described_class.call(position, analysis)
    end
  end

  context 'when risk manager decides to exit (Rupee SL hit)' do
    let(:position) { base_position.merge('ltp' => 93) }
    let(:analysis) do
      base_analysis.merge(
        ltp: 93,
        pnl: (93 - 100) * 75, # -525
        pnl_pct: ((93 - 100) * 75.0 / (100 * 75.0) * 100).round(2), # -7%
        quantity: 75
      )
    end

    it 'calls Orders::Executor with RupeeStopLoss reason' do
      expect(Orders::Executor).to receive(:call).with(position, /^RupeeStopLoss_/, analysis)
      described_class.call(position, analysis)
    end
  end

  context 'when risk manager decides to exit (percentage SL hit)' do
    # before { allow(Charges::Calculator).to receive(:call).and_return(0) }

    let(:position) { base_position.merge('ltp' => 70) }
    let(:analysis) do
      base_analysis.merge(
        ltp: 70,
        pnl: (70 - 100) * 75, # -2250
        pnl_pct: ((70 - 100) * 75.0 / (100 * 75.0) * 100).round(2), # -30%
        quantity: 75
      )
    end

    it 'calls Orders::Executor with RupeeStopLoss reason (rupee SL hits before % SL)' do
      expect(Orders::Executor).to receive(:call).with(position, /^RupeeStopLoss_/, analysis)
      described_class.call(position, analysis)
    end
  end

  context 'when risk manager decides to adjust (trailing stop adjustment)' do
    let(:position) { base_position.merge('ltp' => 130) }
    let(:analysis) do
      # Set max_pct = 25, current pnl_pct = 10 (drawdown = 15% >= option trail buffer)
      base_analysis.merge(
        ltp: 130,
        pnl: (130 - 100) * 75,
        pnl_pct: 10.0,
        quantity: 75
      )
    end

    before do
      # Simulate cache with higher max_pct, so drawdown >= 15%
      allow(Rails.cache).to receive(:read).and_return(25.0)
      allow(Rails.cache).to receive(:write) # don't care about write in this test
    end

    it 'calls Orders::Adjuster with a trigger price' do
      expect(Orders::Adjuster).to receive(:call).with(position, hash_including(:trigger_price))
      described_class.call(position, analysis)
    end
  end

  context 'when risk manager returns neither exit nor adjust' do
    let(:position) { base_position.merge('ltp' => 102) }
    let(:analysis) do
      base_analysis.merge(
        ltp: 102,
        pnl: (102 - 100) * 75, # 150
        pnl_pct: ((102 - 100) * 75.0 / (100 * 75.0) * 100).round(2), # 2%
        quantity: 75
      )
    end

    it 'does not call Executor or Adjuster' do
      expect(Orders::Executor).not_to receive(:call)
      expect(Orders::Adjuster).not_to receive(:call)
      described_class.call(position, analysis)
    end
  end

  context 'when an error occurs' do
    let(:position) { base_position }
    let(:analysis) { base_analysis }

    before do
      allow(Orders::RiskManager).to receive(:call).and_raise(StandardError, 'Manager error')
    end

    it 'logs the error and does not raise' do
      expect(Rails.logger).to receive(:error).with(/\[Orders::Manager\] Error for NIFTY24JUL17500CE: Manager error/)
      expect { described_class.call(position, analysis) }.not_to raise_error
    end
  end
end
