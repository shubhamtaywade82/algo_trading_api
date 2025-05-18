# frozen_string_literal: true

require 'rails_helper'
require 'webmock/rspec'

RSpec.describe 'Exit Management Integration', type: :integration do
  before do
    # Stub TelegramNotifier
    allow(TelegramNotifier).to receive(:send_message)
    # Stub Rails logger
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
    allow(Rails.logger).to receive(:warn)
    # Stub Order and ExitLog
    allow(Order).to receive(:create!).and_return(true)
    allow(ExitLog).to receive(:create!).and_return(true)
    # Prevent real time check
    allow(Time).to receive(:current).and_return(Time.parse('2024-06-19 12:30:00 +0530'))
    allow(Dhanhq::API::Portfolio).to receive(:positions).and_return(positions)

    allow(Orders::Analyzer).to receive(:call).with(stock_position).and_return(
      {
        entry_price: 100.0, ltp: 112.0, quantity: 100,
        pnl: 1200.0, pnl_pct: 12.0, instrument_type: :equity_intraday
      }
    )
    allow(Orders::Analyzer).to receive(:call).with(option_position).and_return(
      {
        entry_price: 50.0, ltp: 85.0, quantity: 75,
        pnl: 2625.0, pnl_pct: 70.0, instrument_type: :option
      }
    )
    allow(Orders::Analyzer).to receive(:call).with(future_position).and_return(
      {
        entry_price: 22_400.0, ltp: 22_550.0, quantity: 15,
        pnl: 2250.0, pnl_pct: 0.67, instrument_type: :future
      }
    )

    allow(Dhanhq::API::Orders).to receive_messages(place: order_response_ok, list: [
                                                     {
                                                       'orderId' => '123456789',
                                                       'securityId' => 'OPTNIFTY24062024CE',
                                                       'orderStatus' => 'PENDING'
                                                     }
                                                   ], modify: order_modify_success)
  end

  let(:stock_position) do
    {
      'securityId' => 'TATASTEEL',
      'exchangeSegment' => 'NSE_EQ',
      'productType' => 'INTRADAY',
      'tradingSymbol' => 'TATASTEEL',
      'buyAvg' => 100.0,
      'ltp' => 112.0,
      'netQty' => 100
    }
  end
  # 3. Webmocks for Dhanhq API
  let(:order_response_ok) do
    {
      'orderId' => '123456789',
      'orderStatus' => 'PENDING'
    }
  end
  let(:order_modify_success) { { 'status' => 'success' } }
  let(:order_modify_fail)    { { 'status' => 'failure', 'omsErrorDescription' => 'Invalid Trigger' } }

  let(:option_position) do
    {
      'securityId' => 'OPTNIFTY24062024CE',
      'exchangeSegment' => 'NSE_FNO',
      'productType' => 'INTRADAY',
      'tradingSymbol' => 'NIFTY24JUN22400CE',
      'buyAvg' => 50.0,
      'ltp' => 85.0,
      'netQty' => 75
    }
  end

  let(:future_position) do
    {
      'securityId' => 'FUTNIFTY24062024',
      'exchangeSegment' => 'NSE_FNO',
      'productType' => 'INTRADAY',
      'tradingSymbol' => 'NIFTY24JUNFUT',
      'buyAvg' => 22_400.0,
      'ltp' => 22_550.0,
      'netQty' => 15
    }
  end

  let(:positions) { [stock_position, option_position, future_position] }

  # 1. Stub Portfolio.positions to return test positions

  # 2. Stub Analyzer to return analysis for each type

  it 'handles exit flow for options, futures, and stocks' do
    # This will invoke all services, including adjuster/executor/manager
    expect { Positions::Manager.call }.not_to raise_error

    # Check that TelegramNotifier is called for both exit (TP) and adjust (SL) flows
    expect(TelegramNotifier).to have_received(:send_message).at_least(:once)
    expect(Order).to have_received(:create!).at_least(:once)
    expect(ExitLog).to have_received(:create!).at_least(:once)
  end

  context 'when adjuster needs to fallback (order modify fails)' do
    before do
      allow(Dhanhq::API::Orders).to receive(:modify).and_return(order_modify_fail)
      # Also stub Orders::Executor in fallback path to avoid double effect
      allow(Orders::Executor).to receive(:call).and_return(true)
    end

    it 'invokes fallback exit and notifies' do
      expect { Orders::Adjuster.call(option_position, { trigger_price: 82 }) }.not_to raise_error
      expect(TelegramNotifier).to have_received(:send_message).with(/Fallback exit initiated/)
      expect(Orders::Executor).to have_received(:call).with(anything, 'FallbackExit', anything)
    end
  end

  context 'when Dhanhq::API::Orders.place fails (order rejected)' do
    before do
      allow(Dhanhq::API::Orders).to receive(:place).and_return({ 'orderId' => nil, 'orderStatus' => 'REJECTED',
                                                                 'message' => 'Margin error' })
    end

    it 'logs error and does not create Order or ExitLog' do
      expect(Order).not_to receive(:create!)
      expect(ExitLog).not_to receive(:create!)
      expect do
        Orders::Executor.call(option_position, 'SL',
                              { entry_price: 50, ltp: 45, quantity: 75, pnl: -375, pnl_pct: -10.0, instrument_type: :option })
      end.not_to raise_error
    end
  end

  context 'when no open order is found for adjuster' do
    before do
      allow(Dhanhq::API::Orders).to receive(:list).and_return([]) # no active order
      allow(Orders::Executor).to receive(:call).and_return(true)
    end

    it 'invokes fallback exit' do
      expect do
        Orders::Adjuster.call(option_position, { trigger_price: 82 })
      end.not_to raise_error
      expect(Orders::Executor).to have_received(:call)
      expect(TelegramNotifier).to have_received(:send_message).with(/Fallback exit initiated/)
    end
  end

  context 'edge case: market close (EOD)' do
    before do
      # EOD hour, should skip
      allow(Time).to receive(:current).and_return(Time.parse('2024-06-19 15:16:00 +0530'))
    end

    it 'logs and skips exits' do
      expect(Rails.logger).to receive(:info).with(/Market closing — skipping exits/)
      expect(Order).not_to receive(:create!)
      Positions::Manager.call
    end
  end

  context 'edge case: StandardError in flow' do
    before do
      allow(Orders::Manager).to receive(:call).and_raise(StandardError, 'Test error')
    end

    it 'rescues and logs error' do
      expect(Rails.logger).to receive(:error).with(/Test error/)
      expect { Positions::Manager.call }.not_to raise_error
    end
  end
end
