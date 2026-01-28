# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Orders::Executor, type: :service do
  let(:position) do
    {
      'securityId' => 'OPT123',
      'netQty' => 75,
      'tradingSymbol' => 'NIFTY24JUL17500CE',
      'ltp' => 100,
      'exchangeSegment' => 'NSE_FNO',
      'productType' => 'INTRADAY'
    }
  end

  let(:analysis) do
    {
      entry_price: 80,
      ltp: 100,
      quantity: 75,
      pnl: 1500,
      pnl_pct: 25,
      instrument_type: :option
    }
  end

  it 'creates order and exit log, sends Telegram' do
    orig_place_order = ENV.fetch('PLACE_ORDER', nil)
    order_double = double(
      'Order',
      save: true,
      order_id: '112111182198',
      id: '112111182198',
      order_status: 'PENDING',
      status: 'PENDING'
    )
    order_class = double('OrderClass')
    allow(order_class).to receive(:new).and_return(order_double)
    stub_const('DhanHQ::Models::Order', order_class)
    allow(Charges::Calculator).to receive(:call).and_return(0)
    ENV['PLACE_ORDER'] = 'true'

    expect(TelegramNotifier).to receive(:send_message).once
    described_class.call(position, 'StopLoss_30%', analysis)
  ensure
    ENV['PLACE_ORDER'] = orig_place_order
  end

  # integration-style: runs real Charges::Calculator, stubs external only (Dhan order, Telegram)
  it 'uses real charges and notifies with correct net PnL' do
    orig_place_order = ENV.fetch('PLACE_ORDER', nil)
    order_double = double(
      'Order',
      save: true,
      order_id: '112111182198',
      id: '112111182198',
      order_status: 'PENDING',
      status: 'PENDING'
    )
    order_class = double('OrderClass')
    allow(order_class).to receive(:new).and_return(order_double)
    stub_const('DhanHQ::Models::Order', order_class)
    allow(TelegramNotifier).to receive(:send_message)
    ENV['PLACE_ORDER'] = 'true'

    described_class.call(position, 'StopLoss_30%', analysis)

    expected_charges = Charges::Calculator.call(position, analysis)
    expected_net_pnl = analysis[:pnl] - expected_charges
    expect(TelegramNotifier).to have_received(:send_message).with(
      a_string_including(expected_net_pnl.to_s)
    )
  ensure
    ENV['PLACE_ORDER'] = orig_place_order
  end
end
