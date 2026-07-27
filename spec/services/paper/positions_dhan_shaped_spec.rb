# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Paper::Positions, '.dhan_shaped' do
  let!(:account) do
    PaperAccount.create!(initial_capital: 1_000_000, available_balance: 1_000_000,
                         config: PaperAccount::DEFAULT_CONFIG.dup)
  end

  def create_position(**attrs)
    account.paper_positions.create!(
      { security_id: '49081', exchange_segment: 'NSE_FNO', product_type: 'MARGIN',
        trading_symbol: 'NIFTY24JUL22000CE', position_type: 'LONG', net_qty: 75,
        buy_qty: 75, buy_avg: 100.0, realized_profit: 0.0, unrealized_profit: 250.0, ltp: 103.0 }.merge(attrs)
    )
  end

  # Callers across this app reach for camelCase and snake_case interchangeably;
  # answering only one spelling reads as a flat position, which is how a paper
  # run silently places the same entry twice.
  it 'answers both the broker spelling and the snake_case one' do
    create_position

    row = described_class.dhan_shaped.first

    expect(row['securityId']).to eq('49081')
    expect(row['security_id']).to eq('49081')
    expect(row['netQty']).to eq(75)
    expect(row['positionType']).to eq('LONG')
    expect(row['exchangeSegment']).to eq('NSE_FNO')
    expect(row['realizedProfit']).to eq(0.0)
  end

  it 'is readable with symbol keys too' do
    create_position

    row = described_class.dhan_shaped.first

    expect(row[:security_id]).to eq('49081')
    expect(row[:securityId]).to eq('49081')
  end

  # Realised P&L lives on the row that closed, so excluding closed positions
  # would leave the daily-loss guard permanently reading zero.
  it 'includes closed positions so realised losses stay visible' do
    create_position(security_id: '49082', position_type: 'CLOSED', net_qty: 0,
                    realized_profit: -4_000.0, unrealized_profit: 0.0)

    losses = described_class.dhan_shaped.sum { |p| p['realizedProfit'].to_f }

    expect(losses).to eq(-4_000.0)
  end

  # Dhan's positions API is day-scoped; the simulated book must be too, or a
  # loss from last week keeps blocking today's entries.
  it 'excludes rows untouched today' do
    travel_to(3.days.ago) { create_position(security_id: '49083') }

    expect(described_class.dhan_shaped.pluck('securityId')).not_to include('49083')
  end
end
