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
    orig = ENV['PLACE_ORDER']
    ENV['PLACE_ORDER'] = 'true'

    expect(TelegramNotifier).to receive(:send_message).once
    described_class.call(position, 'StopLoss_30%', analysis)
  ensure
    ENV['PLACE_ORDER'] = orig
  end
end
