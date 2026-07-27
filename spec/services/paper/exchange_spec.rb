# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Paper::Exchange do
  subject(:exchange) { described_class.new(account: account) }

  let(:account) do
    PaperAccount.create!(
      initial_capital: 1_000_000, available_balance: 1_000_000,
      config: PaperAccount::DEFAULT_CONFIG.merge(
        'market_hours_enforced' => false, 'slippage_bps' => 100, 'fill_probability' => 1.0
      )
    )
  end

  let(:buy_market) do
    { security_id: '1333', exchange_segment: 'NSE_EQ', transaction_type: 'BUY',
      quantity: 10, order_type: 'MARKET', product_type: 'INTRADAY' }
  end

  before do
    Live::TickCache.clear!
    Live::TickCache.put('NSE_EQ', '1333', ltp: 1_500.0)
  end

  after { Live::TickCache.clear! }

  describe 'market orders' do
    it 'fills immediately against the live price' do
      result = exchange.place(buy_market)

      expect(result).to include(paper: true, order_status: 'TRADED', filled_qty: 10)
    end

    # Slippage must always cost the taker; a model that sometimes improved the
    # fill would flatter every backtest.
    it 'applies slippage against the buyer' do
      result = exchange.place(buy_market)

      # 100 bps on 1500 = 15
      expect(result[:average_traded_price]).to eq(1_515.0)
    end

    it 'applies slippage against the seller' do
      result = exchange.place(buy_market.merge(transaction_type: 'SELL'))

      expect(result[:average_traded_price]).to eq(1_485.0)
    end

    it 'debits cash and charges on a buy' do
      exchange.place(buy_market)
      account.reload

      expect(account.available_balance.to_f).to be < 1_000_000
      expect(account.total_charges.to_f).to be > 0
    end

    it 'opens a long position' do
      exchange.place(buy_market)

      position = account.paper_positions.find_by(security_id: '1333')
      expect(position.net_qty).to eq(10)
      expect(position.position_type).to eq('LONG')
    end
  end

  describe 'limit orders' do
    it 'fills a marketable limit at the better price, without market slippage' do
      result = exchange.place(buy_market.merge(order_type: 'LIMIT', price: 1_510.0))

      expect(result[:order_status]).to eq('TRADED')
      expect(result[:average_traded_price]).to eq(1_500.0)
    end

    it 'rests a limit below the market' do
      result = exchange.place(buy_market.merge(order_type: 'LIMIT', price: 1_400.0))

      expect(result[:order_status]).to eq('PENDING')
      expect(result[:filled_qty]).to eq(0)
    end

    # This is the behaviour a resting order exists for: it must eventually fill.
    it 'fills a resting limit when a later tick reaches it' do
      exchange.place(buy_market.merge(order_type: 'LIMIT', price: 1_400.0))

      exchange.process_tick(security_id: '1333', exchange_segment: 'NSE_EQ', ltp: 1_395.0)

      order = account.paper_orders.last
      expect(order.status).to eq('traded')
      expect(order.filled_qty).to eq(10)
    end

    it 'leaves a resting limit alone when the tick does not reach it' do
      exchange.place(buy_market.merge(order_type: 'LIMIT', price: 1_400.0))

      exchange.process_tick(security_id: '1333', exchange_segment: 'NSE_EQ', ltp: 1_450.0)

      expect(account.paper_orders.last.status).to eq('pending')
    end
  end

  describe 'stop orders' do
    it 'rests until the trigger is crossed, then fills' do
      exchange.place(buy_market.merge(order_type: 'STOP_LOSS_MARKET', trigger_price: 1_550.0))
      expect(account.paper_orders.last.status).to eq('pending')

      Live::TickCache.put('NSE_EQ', '1333', ltp: 1_560.0)
      exchange.process_tick(security_id: '1333', exchange_segment: 'NSE_EQ', ltp: 1_560.0)

      expect(account.paper_orders.last.status).to eq('traded')
    end
  end

  describe 'realised P&L' do
    it 'realises only the quantity a fill actually closes' do
      exchange.place(buy_market.merge(order_type: 'LIMIT', price: 1_500.0)) # long 10 @ 1500

      Live::TickCache.put('NSE_EQ', '1333', ltp: 1_600.0)
      exchange.place(buy_market.merge(transaction_type: 'SELL', quantity: 4, order_type: 'LIMIT', price: 1_600.0))

      position = account.paper_positions.find_by(security_id: '1333')
      expect(position.net_qty).to eq(6)
      expect(position.realized_profit.to_f).to eq(400.0) # 4 x (1600 - 1500)
    end

    it 'realises a short covered at a lower price' do
      exchange.place(buy_market.merge(transaction_type: 'SELL', order_type: 'LIMIT', price: 1_500.0))

      Live::TickCache.put('NSE_EQ', '1333', ltp: 1_400.0)
      exchange.place(buy_market.merge(order_type: 'LIMIT', price: 1_400.0))

      position = account.paper_positions.find_by(security_id: '1333')
      expect(position.position_type).to eq('CLOSED')
      expect(position.realized_profit.to_f).to eq(1_000.0) # 10 x (1500 - 1400)
    end

    it 'realises nothing when a fill only extends a position' do
      exchange.place(buy_market.merge(order_type: 'LIMIT', price: 1_500.0))
      exchange.place(buy_market.merge(order_type: 'LIMIT', price: 1_500.0))

      expect(account.paper_positions.find_by(security_id: '1333').realized_profit.to_f).to eq(0.0)
      expect(account.reload.realized_pnl.to_f).to eq(0.0)
    end
  end

  describe 'mark to market' do
    it 'marks an open position against the tick' do
      exchange.place(buy_market.merge(order_type: 'LIMIT', price: 1_500.0))

      exchange.process_tick(security_id: '1333', exchange_segment: 'NSE_EQ', ltp: 1_560.0)

      position = account.paper_positions.find_by(security_id: '1333')
      expect(position.unrealized_profit.to_f).to eq(600.0) # 10 x (1560 - 1500)
    end
  end

  describe 'margin' do
    it 'rejects an order the account cannot fund' do
      account.update!(available_balance: 100)

      result = exchange.place(buy_market.merge(product_type: 'CNC'))

      expect(result).to include(error: true)
      expect(account.paper_orders.last.rejection_reason['code']).to eq('MARGIN')
    end

    it 'blocks margin on a resting order and releases it on cancel' do
      exchange.place(buy_market.merge(order_type: 'LIMIT', price: 1_400.0, product_type: 'CNC'))
      account.reload
      expect(account.blocked_margin.to_f).to be > 0

      exchange.cancel(account.paper_orders.last.id)

      expect(account.reload.blocked_margin.to_f).to eq(0.0)
    end
  end

  describe 'validation' do
    it 'rejects a LIMIT order with no price' do
      result = exchange.place(buy_market.merge(order_type: 'LIMIT'))

      expect(result[:message]).to match(/positive price/)
    end

    it 'rejects an F&O quantity that is not a lot multiple' do
      create(:instrument, security_id: '49081', lot_size: 25, segment: 'derivatives', exchange: 'NSE')

      result = exchange.place(buy_market.merge(security_id: '49081', exchange_segment: 'NSE_FNO', quantity: 30))

      expect(result[:message]).to match(/lot size 25/)
    end

    it 'enforces market hours when configured' do
      account.update!(config: account.settings.merge('market_hours_enforced' => true))
      travel_to(Time.zone.parse('2026-07-26 22:00:00')) do
        expect(described_class.new(account: account).place(buy_market)[:message]).to match(/Market is closed/)
      end
    end
  end

  describe 'super orders' do
    let(:super_entry) do
      buy_market.merge(order_type: 'LIMIT', price: 1_500.0,
                       super_order_params: { target_price: 1_550.0, stop_loss_price: 1_470.0 })
    end

    it 'closes the position when the target is hit' do
      exchange.place(super_entry)

      Live::TickCache.put('NSE_EQ', '1333', ltp: 1_555.0)
      exchange.process_tick(security_id: '1333', exchange_segment: 'NSE_EQ', ltp: 1_555.0)

      entry = account.paper_orders.where(order_category: 'super').first
      expect(entry.reload.status).to eq('closed')
      expect(entry.metadata['exit_leg']).to eq('TARGET')
      expect(account.paper_positions.find_by(security_id: '1333').net_qty).to eq(0)
    end

    it 'closes the position when the stop is hit' do
      exchange.place(super_entry)

      Live::TickCache.put('NSE_EQ', '1333', ltp: 1_465.0)
      exchange.process_tick(security_id: '1333', exchange_segment: 'NSE_EQ', ltp: 1_465.0)

      entry = account.paper_orders.where(order_category: 'super').first
      expect(entry.reload.metadata['exit_leg']).to eq('STOP_LOSS')
    end

    # IndexOrderPayloadBuilder.build_super emits target/stop at the top level,
    # not nested. Only reading a nested :super_order_params meant every real
    # super order was recorded as a plain order and its legs never fired, so
    # the position ran on forever.
    it 'recognises the flat payload the app actually builds' do
      exchange.place(buy_market.merge(order_type: 'LIMIT', price: 1_500.0,
                                      target_price: 1_550.0, stop_loss_price: 1_470.0, trailing_jump: 5.0))

      entry = account.paper_orders.last
      expect(entry.order_category).to eq('super')
      expect(entry.super_order_params).to include('target_price' => 1_550.0, 'stop_loss_price' => 1_470.0)
    end

    it 'closes a flat-payload super order on its target' do
      exchange.place(buy_market.merge(order_type: 'LIMIT', price: 1_500.0,
                                      target_price: 1_550.0, stop_loss_price: 1_470.0))

      Live::TickCache.put('NSE_EQ', '1333', ltp: 1_555.0)
      exchange.process_tick(security_id: '1333', exchange_segment: 'NSE_EQ', ltp: 1_555.0)

      expect(account.paper_orders.where(order_category: 'super').first.reload.metadata['exit_leg']).to eq('TARGET')
      expect(account.paper_positions.find_by(security_id: '1333').net_qty).to eq(0)
    end

    it 'is not treated as a super order without target or stop' do
      exchange.place(buy_market.merge(order_type: 'LIMIT', price: 1_500.0))

      expect(account.paper_orders.last.order_category).to eq('regular')
    end

    it 'leaves the entry open between the levels' do
      exchange.place(super_entry)

      exchange.process_tick(security_id: '1333', exchange_segment: 'NSE_EQ', ltp: 1_510.0)

      expect(account.paper_orders.where(order_category: 'super').first.reload.status).to eq('traded')
    end

    # A trailing_jump that is recorded and then ignored makes every trailing
    # strategy test as a fixed stop: it never gives back the move, so anything
    # that rides a trend and hands profit back looks better than it was.
    describe 'trailing stop' do
      let(:trailing_entry) do
        buy_market.merge(order_type: 'LIMIT', price: 1_500.0, target_price: 1_600.0,
                         stop_loss_price: 1_470.0, trailing_jump: 10.0)
      end

      def tick(price)
        Live::TickCache.put('NSE_EQ', '1333', ltp: price)
        exchange.process_tick(security_id: '1333', exchange_segment: 'NSE_EQ', ltp: price)
      end

      it 'ratchets the stop up in whole jumps as price advances' do
        exchange.place(trailing_entry)

        tick(1_525.0) # +25 from entry: two whole jumps

        entry = account.paper_orders.where(order_category: 'super').first.reload
        expect(entry.metadata['trailed_stop'].to_f).to eq(1_490.0)
      end

      it 'does not move the stop until price travels a full jump' do
        exchange.place(trailing_entry)

        tick(1_508.0)

        expect(account.paper_orders.where(order_category: 'super').first.reload.metadata['trailed_stop']).to be_nil
      end

      it 'never gives the stop back when price retreats' do
        exchange.place(trailing_entry)

        tick(1_530.0)
        tick(1_505.0)

        entry = account.paper_orders.where(order_category: 'super').first.reload
        expect(entry.metadata['trailed_stop'].to_f).to eq(1_500.0)
        expect(entry.status).to eq('traded')
      end

      it 'exits on the trailed stop, well above the original one' do
        exchange.place(trailing_entry)

        tick(1_530.0)  # stop trails to 1500
        tick(1_499.0)  # through the trailed stop, nowhere near the original 1470

        entry = account.paper_orders.where(order_category: 'super').first.reload
        expect(entry.metadata['exit_leg']).to eq('STOP_LOSS')
        expect(account.paper_positions.find_by(security_id: '1333').net_qty).to eq(0)
      end

      it 'trails downward for a short' do
        exchange.place(buy_market.merge(transaction_type: 'SELL', order_type: 'LIMIT', price: 1_500.0,
                                        target_price: 1_400.0, stop_loss_price: 1_530.0, trailing_jump: 10.0))

        tick(1_475.0) # -25 from entry: two whole jumps

        entry = account.paper_orders.where(order_category: 'super').first.reload
        expect(entry.metadata['trailed_stop'].to_f).to eq(1_510.0)
      end
    end
  end

  describe 'partial fills' do
    it 'fills less than the full quantity when configured to' do
      account.update!(config: account.settings.merge(
        'partial_fill_enabled' => true, 'fill_probability' => 0.0, 'partial_fill_min_pct' => 0.3
      ))

      result = described_class.new(account: account).place(buy_market.merge(quantity: 100))

      expect(result[:filled_qty]).to be_between(30, 80)
      expect(account.paper_orders.last.status).to eq('part_traded')
    end
  end

  describe '#exit_all!' do
    it 'closes every open position' do
      exchange.place(buy_market.merge(order_type: 'LIMIT', price: 1_500.0))

      exchange.exit_all!

      expect(account.paper_positions.open_positions).to be_empty
    end
  end
end
