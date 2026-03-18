# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mcp::Tools::ExitPosition do
  describe '.execute' do
    let(:position) do
      {
        'securityId' => '1333',
        'exchangeSegment' => 'NSE_FNO',
        'tradingSymbol' => 'NIFTY2531822000CE',
        'netQty' => 75
      }
    end

    it 'calls Orders::Executor with a MARKET exit' do
      allow(Positions::ActiveCache).to receive(:fetch).and_return(position)
      allow(Orders::Analyzer).to receive(:call).with(position).and_return({ order_type: 'LIMIT', pnl: 10 })
      allow(Orders::Executor).to receive(:call)

      result = described_class.execute(
        'security_id' => '1333',
        'exchange_segment' => 'NSE_FNO',
        'reason' => 'TEST_EXIT'
      )

      expect(result[:success]).to be true
      expect(result[:reason]).to eq('TEST_EXIT')

      expect(Orders::Executor).to have_received(:call).with(
        position,
        'TEST_EXIT',
        hash_including(order_type: 'MARKET')
      )
    end

    it 'returns error when position not found' do
      allow(Positions::ActiveCache).to receive(:fetch).and_return(nil)

      result = described_class.execute('security_id' => '1333', 'exchange_segment' => 'NSE_FNO')
      expect(result[:error]).to include('Position not found')
    end
  end
end

