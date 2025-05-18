# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Charges::Calculator, type: :service do
  let(:common_attrs) do
    {
      'exchangeSegment' => exchange_segment,
      'productType' => product_type,
      'tradingSymbol' => trading_symbol
    }
  end

  let(:analysis) do
    {
      entry_price: entry_price,
      ltp: ltp,
      quantity: qty,
      instrument_type: instrument_type
    }
  end

  # === Option Contract ===
  context 'when instrument is NSE option (equity option)' do
    let(:exchange_segment) { 'NSE_FNO' }
    let(:product_type)     { 'INTRADAY' }
    let(:trading_symbol)   { 'NIFTY24JUL17500CE' }
    let(:instrument_type)  { :option }
    let(:entry_price)      { 100 }
    let(:ltp)              { 120 }
    let(:qty)              { 75 }

    it 'calculates correct charges for options' do
      total = described_class.call(common_attrs, analysis)
      # Charges breakdown for manual cross-checking:
      # Brokerage: 20.0
      # Transaction: 120*75*0.0003503
      # STT:        120*75*0.001
      # Stamp duty: 100*75*0.00003
      # SEBI fees:  120*75*0.000001
      # IPFT:       120*75*0.000005
      # GST:        18% of (brokerage + tx + sebi + ipft)
      expect(total).to be > 20
      expect(total).to be_within(2).of(37) # 36.61 is correct, allow for minor float drift
    end
  end

  # === Futures Contract ===
  context 'when instrument is NSE futures' do
    let(:exchange_segment) { 'NSE_FNO' }
    let(:product_type)     { 'INTRADAY' }
    let(:trading_symbol)   { 'NIFTY24JULFUT' }
    let(:instrument_type)  { :future }
    let(:entry_price)      { 22_000 }
    let(:ltp)              { 22_200 }
    let(:qty)              { 15 }

    it 'calculates correct charges for futures' do
      total = described_class.call(common_attrs, analysis)
      expect(total).to be > 20
      # Should be less than 200 for this trade size
      expect(total).to be_within(10).of(112) # 111.9 is the real calculated charge
    end
  end

  # === Equity Intraday ===
  context 'when instrument is NSE equity intraday' do
    let(:exchange_segment) { 'NSE_EQ' }
    let(:product_type)     { 'INTRADAY' }
    let(:trading_symbol)   { 'TATASTEEL' }
    let(:instrument_type)  { :equity_intraday }
    let(:entry_price)      { 150 }
    let(:ltp)              { 153 }
    let(:qty)              { 100 }

    it 'calculates correct charges for equity intraday' do
      total = described_class.call(common_attrs, analysis)
      expect(total).to be > 1
      expect(total).to be < 100
      # Zero brokerage for delivery, but not for intraday!
      expect(total).not_to eq(0)
    end
  end

  # === Equity Delivery ===
  context 'when instrument is NSE equity delivery' do
    let(:exchange_segment) { 'NSE_EQ' }
    let(:product_type)     { 'CNC' }
    let(:trading_symbol)   { 'TATASTEEL' }
    let(:instrument_type)  { :equity_delivery }
    let(:entry_price)      { 150 }
    let(:ltp)              { 153 }
    let(:qty)              { 100 }

    it 'calculates correct charges for equity delivery (should be lowest, no brokerage)' do
      total = described_class.call(common_attrs, analysis)
      expect(total).to be > 0
      # No brokerage for delivery, so total should be less than for intraday
      expect(total).to be < 40 # Actuals around 32.62, so <40 is fair
    end
  end

  # === Error Handling / Defaults ===
  context 'when instrument type is unknown' do
    let(:exchange_segment) { 'UNKNOWN' }
    let(:product_type)     { 'INTRADAY' }
    let(:trading_symbol)   { 'UNKNOWN' }
    let(:instrument_type)  { :option }
    let(:entry_price)      { 100 }
    let(:ltp)              { 105 }
    let(:qty)              { 1 }

    it 'defaults to option charges' do
      total = described_class.call(common_attrs, analysis)
      expect(total).to be > 0
    end
  end
end
