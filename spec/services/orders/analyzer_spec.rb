# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Orders::Analyzer, type: :service do
  let(:base_position) do
    {
      'securityId' => 'OPT123',
      'tradingSymbol' => 'NIFTY24JUL17500CE',
      'ltp' => 105.50,
      'buyAvg' => 100,
      'netQty' => 75,
      'exchangeSegment' => 'NSEFO',
      'productType' => 'INTRADAY'
    }
  end

  it 'calculates pnl and pnl_pct for a long option position' do
    analysis = described_class.call(base_position)
    expect(analysis[:entry_price]).to eq(100)
    expect(analysis[:ltp]).to eq(105.5)
    expect(analysis[:quantity]).to eq(75)
    expect(analysis[:pnl]).to eq(((105.5 - 100) * 75).round(2))
    expect(analysis[:pnl_pct]).to eq((((105.5 - 100) * 75) / (100 * 75).abs * 100).round(2))
    expect(analysis[:instrument_type]).to eq(:option)
  end

  it 'calculates pnl for a short option position' do
    position = base_position.merge('netQty' => -75)
    analysis = described_class.call(position)
    expect(analysis[:pnl]).to eq(((100 - 105.5) * 75).round(2))
    expect(analysis[:pnl_pct]).to eq((((100 - 105.5) * 75) / (100 * 75).abs * 100).round(2))
  end

  it 'detects instrument_type as :stock if not FNO or INTRADAY' do
    position = base_position.merge('exchangeSegment' => 'NSE_EQ', 'productType' => 'CNC')
    analysis = described_class.call(position)
    expect(analysis[:instrument_type]).to eq(:stock)
  end
end
