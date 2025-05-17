# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Orders::Executor, type: :service do
  let(:position) do
    {
      'securityId' => 'OPT123',
      'netQty' => 75,
      'tradingSymbol' => 'NIFTY24JUL17500CE',
      'ltp' => 100,
      'exchangeSegment' => 'NSEFO',
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

  before do
    # Stub external dependencies
    allow(Dhanhq::API::Orders).to receive(:place).and_return({
                                                               'orderId' => '112111182198',
                                                               'orderStatus' => 'PENDING'
                                                             })

    allow(ExitLog).to receive(:create!)
    allow(Order).to receive(:create!)
    allow(TelegramNotifier).to receive(:send_message)
  end

  it 'creates order and exit log, sends Telegram' do
    expect(Order).to receive(:create!).once
    expect(ExitLog).to receive(:create!).once
    expect(TelegramNotifier).to receive(:send_message).once

    described_class.call(position, 'StopLoss_30%', analysis)
  end
end
