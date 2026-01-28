# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Orders::Manager, type: :service do
  include JsonFixtureHelper

  subject(:service_call) { described_class.call(position.deep_dup, analysis.deep_dup) }

  let(:position) do
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

  let(:analysis) do
    {
      entry_price: 100,
      ltp: 110,
      pnl: 750,
      pnl_pct: 10.0,
      quantity: 75,
      instrument_type: :option,
      order_type: 'MARKET'
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

  # ───────────────────────── decision table ──────────────────────── #
  decisions = [
    { title: 'take-profit',
      decision: { exit: true, exit_reason: 'TakeProfit', order_type: 'MARKET' },
      expect_executor_reason: 'TakeProfit',
      expect_adjust: false },

    { title: 'danger-zone',
      decision: { exit: true, exit_reason: 'DangerZone', order_type: 'LIMIT' },
      expect_executor_reason: 'DangerZone',
      expect_adjust: false },

    { title: 'percent stop-loss',
      decision: { exit: true, exit_reason: 'StopLoss', order_type: 'MARKET' },
      expect_executor_reason: 'StopLoss',
      expect_adjust: false },

    { title: 'trailing adjust',
      decision: { exit: false, adjust: true, adjust_params: { trigger_price: 97.5 } },
      expect_executor: false,
      expect_adjust: true },

    { title: 'no-action',
      decision: { exit: false, adjust: false },
      expect_executor: false,
      expect_adjust: false }
  ]

  decisions.each do |row|
    context "when RiskManager returns #{row[:title]}" do
      before { allow(Orders::RiskManager).to receive(:call).and_return(row[:decision]) }

      it 'invokes correct downstream service' do
        if row.fetch(:expect_executor, true)
          expect(Orders::Executor).to receive(:call)
            .with(position, row[:expect_executor_reason], hash_including(:pnl, :order_type))
        else
          expect(Orders::Executor).not_to receive(:call)
        end

        if row[:expect_adjust]
          expect(Orders::Adjuster).to receive(:call)
            .with(position, hash_including(:trigger_price))
        else
          expect(Orders::Adjuster).not_to receive(:call)
        end

        service_call
      end
    end
  end

  # ───────────────────── error-handling branch ───────────────────── #
  context 'when RiskManager raises' do
    before { allow(Orders::RiskManager).to receive(:call).and_raise(StandardError, 'RM boom') }

    it 'logs but does not raise further' do
      expect(Rails.logger).to receive(:error).with(/RM boom/)
      expect { service_call }.not_to raise_error
    end
  end

  # it 'exits on take profit (TP)' do
  #   position = base_position.merge('ltp' => 161)
  #   analysis = base_analysis.merge(
  #     ltp: 161,
  #     pnl: (161 - 100) * 75,
  #     pnl_pct: 61.0,
  #     quantity: 75
  #   )

  #   expect(Orders::Executor).to receive(:call).with(position, a_string_matching(/^TakeProfit_Net_/), analysis)
  #   described_class.call(position, analysis)
  # end

  # it 'exits on rupee SL danger zone' do
  #   position = base_position.merge('ltp' => 93)
  #   analysis = base_analysis.merge(pnl: -525, pnl_pct: -7.0, ltp: 93)

  #   allow(Rails.cache).to receive(:read).and_return({ max_pct: -7.0, danger_zone_count: 3 })

  #   expect(Orders::Executor).to receive(:call).with(
  #     position, a_string_starting_with('DangerZone_'), analysis
  #   )
  #   described_class.call(position, analysis)
  # end

  # it 'exits on deep rupee loss (still DangerZone)' do
  #   position = base_position.merge('ltp' => 59)
  #   analysis = base_analysis.merge(pnl: -3075, pnl_pct: -41.0, ltp: 59)

  #   expect(Orders::Executor).to receive(:call).with(
  #     position, a_string_starting_with('DangerZone_'), analysis
  #   )

  #   described_class.call(position, analysis)
  # end

  # it 'exits on percentage stop loss but falls into DangerZone first' do
  #   position = base_position.merge('ltp' => 69)
  #   analysis = base_analysis.merge(pnl: -2325, pnl_pct: -31.0, ltp: 69)

  #   allow(Rails.cache).to receive(:read).and_return({ max_pct: -31.0, danger_zone_count: 3 })

  #   expect(Orders::Executor).to receive(:call).with(
  #     position, a_string_starting_with('DangerZone_'), analysis
  #   )
  #   described_class.call(position, analysis)
  # end

  # it 'exits on break-even trail (pnl_pct >= 40%, ltp <= entry)' do
  #   position = base_position.merge('ltp' => 100)
  #   analysis = base_analysis.merge(
  #     ltp: 100,
  #     pnl: 0,
  #     pnl_pct: 40.0,
  #     quantity: 75
  #   )

  #   expect(Orders::Executor).to receive(:call).with(position, a_string_starting_with('BreakEven_Trail_'), analysis)
  #   described_class.call(position, analysis)
  # end

  # it 'adjusts trailing stop loss when drawdown exceeds buffer' do
  #   position = base_position.merge('ltp' => 130)
  #   analysis = base_analysis.merge(pnl: 2250, pnl_pct: 10.0, ltp: 130)

  #   allow(Rails.cache).to receive(:read).and_return({ max_pct: 25.0, danger_zone_count: 0 })
  #   allow(Rails.cache).to receive(:write)

  #   expect(Orders::Adjuster).to receive(:call).with(
  #     position, hash_including(:trigger_price)
  #   )
  #   described_class.call(position, analysis)
  # end

  # it 'does nothing when neither exit nor adjust conditions are met' do
  #   position = base_position.merge('ltp' => 105)
  #   analysis = base_analysis.merge(
  #     ltp: 105,
  #     pnl: 375,
  #     pnl_pct: 5.0,
  #     quantity: 75
  #   )

  #   expect(Orders::Executor).not_to receive(:call)
  #   expect(Orders::Adjuster).not_to receive(:call)

  #   described_class.call(position, analysis)
  # end

  # it 'logs error when risk manager raises' do
  #   position = base_position
  #   analysis = base_analysis

  #   allow(Orders::RiskManager).to receive(:call).and_raise(StandardError, 'RM failure')

  #   expect(Rails.logger).to receive(:error).with(/\[Orders::Manager\] Error.*RM failure/)
  #   expect { described_class.call(position, analysis) }.not_to raise_error
  # end

  # Stub only HTTP/Telegram; real RiskManager (and thus decision logic) runs.
  context 'integration: stubs only external boundaries' do
    let(:position_integration) do
      {
        'tradingSymbol' => 'NIFTY24JUL17500CE',
        'securityId' => 'OPT123',
        'exchangeSegment' => 'NSE_FNO',
        'buyAvg' => 100,
        'netQty' => 75,
        'ltp' => 135,
        'productType' => 'INTRADAY'
      }
    end

    # pnl_pct 35%, take_profit_threshold for option = entry*quantity*0.3 = 2250; net_pnl >= 2250 triggers TP.
    let(:analysis_integration) do
      {
        entry_price: 100,
        ltp: 135,
        pnl: 2625,
        pnl_pct: 35.0,
        quantity: 75,
        instrument_type: :option,
        order_type: 'MARKET'
      }
    end

    before do
      allow(Orders::RiskManager).to receive(:call).and_call_original
    end

    it 'runs real RiskManager and invokes Executor when take-profit is hit' do
      expect(Orders::Executor).to receive(:call).with(
        position_integration,
        'TakeProfit',
        hash_including(:pnl, order_type: 'MARKET')
      )
      expect(Orders::Adjuster).not_to receive(:call)

      described_class.call(position_integration, analysis_integration)
    end
  end
end
