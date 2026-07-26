# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Paper::CostCalculator do
  subject(:calculator) { described_class.new }

  def charges(**overrides)
    calculator.calculate(transaction_type: 'BUY', exchange_segment: 'NSE_EQ',
                         product_type: 'INTRADAY', quantity: 100, price: 1_000.0, **overrides)
  end

  describe 'equity intraday' do
    it 'caps brokerage at the flat fee' do
      # 0.03% of 100,000 = 30, capped at 20
      expect(charges[:brokerage]).to eq(20.0)
    end

    it 'charges the percentage when it is lower than the cap' do
      expect(charges(quantity: 1, price: 100.0)[:brokerage]).to eq(0.03)
    end

    # STT asymmetry is the main reason an intraday paper P&L overstates profit
    # when charges are ignored.
    it 'charges STT on the sell side only' do
      expect(charges(transaction_type: 'BUY')[:stt]).to eq(0.0)
      expect(charges(transaction_type: 'SELL')[:stt]).to be > 0
    end

    it 'charges stamp duty on the buy side only' do
      expect(charges(transaction_type: 'BUY')[:stamp_duty]).to be > 0
      expect(charges(transaction_type: 'SELL')[:stamp_duty]).to eq(0.0)
    end
  end

  describe 'equity delivery' do
    it 'has zero brokerage' do
      expect(charges(product_type: 'CNC')[:brokerage]).to eq(0.0)
    end

    it 'charges STT on both sides' do
      expect(charges(product_type: 'CNC', transaction_type: 'BUY')[:stt]).to be > 0
      expect(charges(product_type: 'CNC', transaction_type: 'SELL')[:stt]).to be > 0
    end
  end

  describe 'F&O' do
    it 'charges the flat brokerage regardless of turnover' do
      expect(charges(exchange_segment: 'NSE_FNO')[:brokerage]).to eq(20.0)
      expect(charges(exchange_segment: 'NSE_FNO', quantity: 1, price: 10.0)[:brokerage]).to eq(20.0)
    end
  end

  describe 'GST' do
    # GST applies to brokerage and exchange fees, not the statutory levies.
    it 'is charged on brokerage and exchange charges only' do
      result = charges
      expected = ((result[:brokerage] + result[:exchange_charges]) * 0.18).round(2)

      expect(result[:gst]).to eq(expected)
    end
  end

  it 'sums the components into the total' do
    result = charges
    parts = result.values_at(:brokerage, :stt, :exchange_charges, :stamp_duty, :sebi_tax, :gst).sum

    expect(result[:total]).to be_within(0.01).of(parts)
  end

  it 'returns zeroes for a zero-value fill' do
    expect(charges(quantity: 0)[:total]).to eq(0.0)
  end
end
