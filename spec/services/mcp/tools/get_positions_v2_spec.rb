# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mcp::Tools::GetPositionsV2 do
  describe '.execute' do
    let(:pos) do
      {
        'tradingSymbol' => 'NIFTY2531822000CE',
        'securityId' => '1333',
        'exchangeSegment' => 'NSE_FNO',
        'netQty' => 75,
        'costPrice' => 120.0,
        'productType' => 'INTRADAY',
        'drvExpiryDate' => '2026-03-27'
      }
    end

    let(:analysis) do
      {
        entry_price: 120.0,
        ltp: 150.0,
        pnl: 2250.0,
        pnl_pct: 25.0
      }
    end

    before do
      allow(Positions::ActiveCache).to receive(:all_positions).and_return([pos])
      allow(Orders::Analyzer).to receive(:call).with(pos).and_return(analysis)
    end

    it 'returns enriched positions' do
      result = described_class.execute({})

      expect(result[:count]).to eq(1)
      expect(result[:positions].size).to eq(1)

      p = result[:positions].first
      expect(p[:trading_symbol]).to eq('NIFTY2531822000CE')
      expect(p[:security_id]).to eq('1333')
      expect(p[:exchange_segment]).to eq('NSE_FNO')
      expect(p[:net_qty]).to eq(75)
      expect(p[:entry_price]).to eq(120.0)
      expect(p[:ltp]).to eq(150.0)
      expect(p[:unrealized_pnl]).to eq(2250.0)
      expect(p[:pnl_pct]).to eq(25.0)
      expect(p[:product_type]).to eq('INTRADAY')
      expect(p[:drv_expiry_date]).to eq('2026-03-27')
    end
  end
end

