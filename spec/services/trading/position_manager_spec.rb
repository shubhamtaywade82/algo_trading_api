# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trading::PositionManager, type: :service do
  let(:security_id) { '1333' }
  let(:exchange_segment) { 'NSE_FNO' }

  let(:position) do
    {
      'securityId' => security_id,
      'exchangeSegment' => exchange_segment,
      'tradingSymbol' => 'NIFTY2531822000CE',
      'netQty' => 75,
      'costPrice' => 120.0,
      'productType' => 'INTRADAY',
      'dhanClientId' => 'client_001',
      'ltp' => 150.0
    }
  end

  before do
    allow(Positions::ActiveCache).to receive(:fetch).with(security_id, exchange_segment).and_return(position)
  end

  describe '#call — position not found' do
    before do
      allow(Positions::ActiveCache).to receive(:fetch).with(security_id, exchange_segment).and_return(nil)
    end

    it 'returns failure result' do
      result = described_class.call(
        security_id: security_id,
        exchange_segment: exchange_segment,
        action: :move_sl_to_be
      )
      expect(result.success).to be false
      expect(result.message).to eq('Position not found')
    end
  end

  describe ':move_sl_to_be' do
    it 'calls Orders::Adjuster with entry price and returns success' do
      allow(Orders::Adjuster).to receive(:call).and_return(true)

      result = described_class.call(
        security_id: security_id,
        exchange_segment: exchange_segment,
        action: :move_sl_to_be
      )

      expect(Orders::Adjuster).to have_received(:call).with(position, { trigger_price: 120.0 })
      expect(result.success).to be true
      expect(result.action).to eq(:move_sl_to_be)
      expect(result.details[:new_trigger_price]).to eq(120.0)
    end

    context 'when entry price is zero' do
      let(:position) { super().merge('costPrice' => 0) }

      it 'returns failure without calling Adjuster' do
        result = described_class.call(
          security_id: security_id,
          exchange_segment: exchange_segment,
          action: :move_sl_to_be
        )
        expect(result.success).to be false
        expect(result.message).to include('Entry price unavailable')
      end
    end
  end

  describe ':trail_sl' do
    let(:analysis) { { ltp: 150.0, long: true } }

    before do
      allow(Orders::Analyzer).to receive(:call).with(position).and_return(analysis)
    end

    it 'computes new trigger at default 5% below LTP for long position' do
      expected_trigger = (150.0 * (1 - 5.0 / 100.0)).round(2)
      allow(Orders::Adjuster).to receive(:call).and_return(true)

      result = described_class.call(
        security_id: security_id,
        exchange_segment: exchange_segment,
        action: :trail_sl
      )

      expect(Orders::Adjuster).to have_received(:call).with(position, { trigger_price: expected_trigger })
      expect(result.success).to be true
      expect(result.details[:new_trigger_price]).to eq(expected_trigger)
      expect(result.details[:trail_pct]).to eq(5.0)
    end

    it 'computes new trigger at custom trail_pct above LTP for short position' do
      allow(Orders::Analyzer).to receive(:call).with(position).and_return({ ltp: 150.0, long: false })
      expected_trigger = (150.0 * (1 + 3.0 / 100.0)).round(2)
      allow(Orders::Adjuster).to receive(:call).and_return(true)

      result = described_class.call(
        security_id: security_id,
        exchange_segment: exchange_segment,
        action: :trail_sl,
        params: { trail_pct: 3.0 }
      )

      expect(Orders::Adjuster).to have_received(:call).with(position, { trigger_price: expected_trigger })
      expect(result.success).to be true
      expect(result.details[:new_trigger_price]).to eq(expected_trigger)
    end

    it 'returns failure when LTP is zero' do
      allow(Orders::Analyzer).to receive(:call).with(position).and_return({ ltp: 0, long: true })

      result = described_class.call(
        security_id: security_id,
        exchange_segment: exchange_segment,
        action: :trail_sl
      )
      expect(result.success).to be false
      expect(result.message).to include('LTP unavailable')
    end
  end

  describe ':partial_exit' do
    it 'calls Orders::Gateway with half qty and returns success' do
      allow(Orders::Gateway).to receive(:place_order).and_return({ order_id: 'ORD001', order_status: 'PENDING' })

      result = described_class.call(
        security_id: security_id,
        exchange_segment: exchange_segment,
        action: :partial_exit
      )

      expect(Orders::Gateway).to have_received(:place_order).with(
        hash_including('quantity' => 75, 'transactionType' => 'SELL'),
        source: 'mcp_partial_exit'
      )
      expect(result.success).to be true
      expect(result.details[:qty_exited]).to eq(75)
    end

    context 'with a 2-lot position (qty 150, lot_size 75)' do
      let(:position) { super().merge('netQty' => 150) }

      it 'exits 1 lot (75 qty)' do
        allow(Orders::Gateway).to receive(:place_order).and_return({ order_id: 'ORD002', order_status: 'PENDING' })

        result = described_class.call(
          security_id: security_id,
          exchange_segment: exchange_segment,
          action: :partial_exit
        )

        expect(Orders::Gateway).to have_received(:place_order).with(
          hash_including('quantity' => 75, 'transactionType' => 'SELL'),
          source: 'mcp_partial_exit'
        )
        expect(result.details[:qty_exited]).to eq(75)
      end
    end

    context 'with a 3-lot position (qty 225, lot_size 75)' do
      let(:position) { super().merge('netQty' => 225) }

      it 'exits 2 lots (150 qty)' do
        allow(Orders::Gateway).to receive(:place_order).and_return({ order_id: 'ORD003', order_status: 'PENDING' })

        result = described_class.call(
          security_id: security_id,
          exchange_segment: exchange_segment,
          action: :partial_exit
        )

        expect(Orders::Gateway).to have_received(:place_order).with(
          hash_including('quantity' => 150, 'transactionType' => 'SELL'),
          source: 'mcp_partial_exit'
        )
        expect(result.details[:qty_exited]).to eq(150)
      end
    end
  end

  describe ':force_exit' do
    it 'calls Orders::Executor and returns success' do
      analysis = { ltp: 150.0, long: true, order_type: 'MARKET' }
      allow(Orders::Analyzer).to receive(:call).with(position).and_return(analysis)
      allow(Orders::Executor).to receive(:call).and_return(nil)

      result = described_class.call(
        security_id: security_id,
        exchange_segment: exchange_segment,
        action: :force_exit
      )

      expect(Orders::Executor).to have_received(:call).with(
        position,
        'MCP_FORCE_EXIT',
        hash_including(order_type: 'MARKET')
      )
      expect(result.success).to be true
      expect(result.action).to eq(:force_exit)
    end
  end

  describe 'unknown action' do
    it 'returns failure with unknown action message' do
      result = described_class.call(
        security_id: security_id,
        exchange_segment: exchange_segment,
        action: :unknown_action
      )
      expect(result.success).to be false
      expect(result.message).to include('Unknown action')
    end
  end
end

