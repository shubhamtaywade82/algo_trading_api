# frozen_string_literal: true

require 'rails_helper'

# The two session boundaries the simulated book needs to behave like a broker's:
# squaring off intraday at the close, and rolling onto a new trading day.
RSpec.describe 'Paper day session' do
  let(:account) do
    PaperAccount.create!(
      initial_capital: 1_000_000, available_balance: 1_000_000,
      config: PaperAccount::DEFAULT_CONFIG.merge('market_hours_enforced' => false, 'slippage_bps' => 0)
    )
  end

  before do
    Live::TickCache.clear!
    Live::TickCache.put('NSE_EQ', '1333', ltp: 1_500.0)
  end

  after { Live::TickCache.clear! }

  def open_position(product_type: 'INTRADAY', **attrs)
    account.paper_positions.create!(
      { security_id: '1333', exchange_segment: 'NSE_EQ', product_type: product_type,
        position_type: 'LONG', net_qty: 10, buy_qty: 10, buy_avg: 1_400.0 }.merge(attrs)
    )
  end

  def resting_order(**attrs)
    account.paper_orders.create!(
      { security_id: '1333', exchange_segment: 'NSE_EQ', transaction_type: 'BUY', order_type: 'LIMIT',
        product_type: 'INTRADAY', validity: 'DAY', quantity: 10, price: 1_000.0, status: 'pending' }.merge(attrs)
    )
  end

  describe Paper::EodSquareOff do
    it 'closes an intraday position at the close' do
      open_position

      expect(described_class.call(account: account)).to eq(1)
      expect(account.paper_positions.open_positions).to be_empty
    end

    # MARGIN (NRML) and CNC are carry-forward products at the broker; squaring
    # them off would invent an exit no real book would have taken.
    it 'leaves carry-forward products alone' do
      open_position(product_type: 'MARGIN', security_id: '49081', exchange_segment: 'NSE_FNO')
      open_position(product_type: 'CNC', security_id: '2885')

      expect(described_class.call(account: account)).to eq(0)
      expect(account.paper_positions.open_positions.count).to eq(2)
    end

    it 'cancels working intraday orders so none survive the session' do
      order = resting_order

      described_class.call(account: account)

      expect(order.reload.status).to eq('cancelled')
    end

    it 'runs once a day however often it is asked' do
      open_position

      expect(described_class.call(account: account)).to eq(1)
      expect(described_class.call(account: account.reload)).to eq(0)
    end

    describe '.due?' do
      it 'is due at the cut-off on a weekday' do
        expect(described_class.due?(now: Time.zone.parse('2026-07-27 15:16'))).to be(true)
      end

      it 'is not due mid-session' do
        expect(described_class.due?(now: Time.zone.parse('2026-07-27 11:00'))).to be(false)
      end

      it 'is never due at a weekend' do
        expect(described_class.due?(now: Time.zone.parse('2026-07-26 15:30'))).to be(false)
      end
    end
  end

  describe Paper::DayRollover do
    before { account.update!(last_rolled_on: 2.days.ago.to_date) }

    it 'expires a DAY order left resting from a previous session' do
      order = resting_order

      described_class.ensure!(account: account)

      expect(order.reload.status).to eq('expired')
    end

    it 'returns the margin an expiring order had blocked' do
      account.update!(blocked_margin: 3_000, utilized_margin: 3_000)
      resting_order(metadata: { 'blocked_margin' => 3_000 })

      described_class.ensure!(account: account)

      expect(account.reload.blocked_margin.to_f).to eq(0.0)
    end

    it 'does nothing twice in one day' do
      expect(described_class.ensure!(account: account)).to be(true)
      expect(described_class.ensure!(account: account.reload)).to be(false)
    end

    # A book that has never been rolled is starting its first session, not
    # recovering from a missed one.
    it 'treats a fresh book as already current' do
      account.update!(last_rolled_on: nil)
      order = resting_order

      expect(described_class.ensure!(account: account)).to be(false)
      expect(order.reload.status).to eq('pending')
      expect(account.reload.last_rolled_on).to eq(Time.current.in_time_zone(described_class::ZONE).to_date)
    end
  end
end
