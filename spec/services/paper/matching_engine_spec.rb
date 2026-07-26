# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Paper::MatchingEngine do
  def engine(**config)
    described_class.new({ 'slippage_model' => 'fixed_bps', 'slippage_bps' => 100 }.merge(config))
  end

  def price_for(engine, **overrides)
    engine.fill_price(order_type: 'MARKET', limit_price: nil, market_price: 100.0,
                      transaction_type: 'BUY', quantity: 10, security_id: '1', exchange_segment: 'NSE_EQ', **overrides)
  end

  before { Live::TickCache.clear! }

  after { Live::TickCache.clear! }

  describe 'slippage direction' do
    # Slippage that ever improved a fill would make backtests lie.
    it 'costs the buyer' do
      expect(price_for(engine)).to eq(101.0)
    end

    it 'costs the seller' do
      expect(price_for(engine, transaction_type: 'SELL')).to eq(99.0)
    end
  end

  describe 'slippage models' do
    it 'applies none when configured' do
      expect(price_for(engine(slippage_model: 'none'))).to eq(100.0)
    end

    it 'uses half the live spread when depth is cached' do
      Live::TickCache.put('NSE_EQ', '1', ltp: 100.0, depth: [{ bid_price: 99.0, ask_price: 101.0 }])

      # Half of a 2.00 spread = 1.00
      expect(price_for(engine(slippage_model: 'spread_based'))).to eq(101.0)
    end

    it 'falls back to fixed bps when no depth is available' do
      expect(price_for(engine(slippage_model: 'spread_based'))).to eq(101.0)
    end

    # Square-root impact: quadrupling size roughly doubles the cost.
    it 'scales volume-based slippage sub-linearly with size' do
      Live::TickCache.put('NSE_EQ', '1', ltp: 100.0, volume: 100_000)
      eng = engine(slippage_model: 'volume_based')

      small = price_for(eng, quantity: 1_000) - 100.0
      large = price_for(eng, quantity: 4_000) - 100.0

      expect(large / small).to be_within(0.05).of(2.0)
    end
  end

  describe 'limit marketability' do
    it 'fills a buy limit at or through the market' do
      expect(price_for(engine, order_type: 'LIMIT', limit_price: 105.0)).to eq(100.0)
    end

    it 'does not fill a buy limit below the market' do
      expect(price_for(engine, order_type: 'LIMIT', limit_price: 95.0)).to be_nil
    end

    it 'does not fill a sell limit above the market' do
      expect(price_for(engine, order_type: 'LIMIT', limit_price: 105.0, transaction_type: 'SELL')).to be_nil
    end

    it 'never fills a limit worse than its price' do
      fill = price_for(engine, order_type: 'LIMIT', limit_price: 100.5)

      expect(fill).to be <= 100.5
    end
  end

  it 'returns nil without a usable market price' do
    expect(price_for(engine, market_price: 0)).to be_nil
  end

  describe 'fill quantity' do
    it 'fills fully when partial fills are disabled' do
      expect(engine.fill_quantity(100)).to eq(100)
    end

    it 'fills partially within the configured band' do
      eng = engine(partial_fill_enabled: true, fill_probability: 0.0, partial_fill_min_pct: 0.3)

      expect(eng.fill_quantity(100)).to be_between(30, 80)
    end

    it 'always fills at least one unit' do
      eng = engine(partial_fill_enabled: true, fill_probability: 0.0)

      expect(eng.fill_quantity(1)).to eq(1)
    end
  end
end
