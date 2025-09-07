# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Positions::Manager, type: :service do
  let(:valid_position) do
    {
      'netQty' => 75,
      'buyAvg' => 100,
      'securityId' => 'OPT1',
      'exchangeSegment' => 'NSE_FNO',
      'productType' => 'INTRADAY',
      'tradingSymbol' => 'NIFTY24JUL17500CE',
      'unrealizedProfit' => 1500 # For LTP estimation!
    }
  end

  let(:invalid_position) do
    {
      'netQty' => 0, 'buyAvg' => 0, 'ltp' => 0, 'securityId' => 'OPT2',
      'exchangeSegment' => 'NSEFO', 'productType' => 'INTRADAY', 'tradingSymbol' => 'NIFTY24JUL17600CE'
    }
  end

  before do
    allow(Rails.logger).to receive(:error)
    allow(Rails.logger).to receive(:info)
    # Stub Orders::Analyzer and Orders::Manager for simplicity—remove if you want their real side effects
    allow(Orders::Analyzer).to receive(:call).and_return({ dummy: :data })
    allow(Orders::Manager).to receive(:call)
    # Ensure cache is empty so it falls back to DhanHQ API
    allow(Positions::ActiveCache).to receive(:all).and_return({})
    # Mock time to be during market hours (before 15:15)
    allow(Time).to receive(:current).and_return(Time.zone.local(2024, 1, 1, 14, 0))
  end

  # Helper to stub Dhanhq positions API (adjust URL to real endpoint if needed)
  def stub_dhan_positions(positions)
    allow(Dhanhq::API::Portfolio).to receive(:positions).and_return(positions)
  end

  context 'with mixed valid/invalid positions' do
    before do
      stub_dhan_positions([valid_position, invalid_position])
      valid_position['ltp'] = 120.0
    end

    it 'calls Orders::Manager only for valid positions' do
      # Use hash_including to match the position with ltp field added
      expect(Orders::Analyzer).to receive(:call).with(hash_including(
        'netQty' => 75,
        'buyAvg' => 100,
        'securityId' => 'OPT1',
        'ltp' => 120.0
      )).and_return({ dummy: :data })

      expect(Orders::Manager).to receive(:call).with(hash_including(
        'netQty' => 75,
        'buyAvg' => 100,
        'securityId' => 'OPT1',
        'ltp' => 120.0
      ), { dummy: :data })

      expect(Orders::Manager).not_to receive(:call).with(invalid_position, anything)
      described_class.call
    end
  end

  context 'when all positions are invalid' do
    before do
      stub_dhan_positions([invalid_position])
    end

    it 'does not call Orders::Manager or Analyzer' do
      expect(Orders::Analyzer).not_to receive(:call)
      expect(Orders::Manager).not_to receive(:call)
      described_class.call
    end
  end

  context 'when positions are empty' do
    before do
      stub_dhan_positions([])
    end

    it 'does not call Orders::Manager or Analyzer' do
      expect(Orders::Analyzer).not_to receive(:call)
      expect(Orders::Manager).not_to receive(:call)
      described_class.call
    end
  end

  context 'when Orders::Manager raises an error' do
    before do
      stub_dhan_positions([valid_position])
      allow(Orders::Analyzer).to receive(:call).and_return({ dummy: :data })
      allow(Orders::Manager).to receive(:call).and_raise(StandardError, 'Boom')
    end

    it 'rescues and logs error' do
      expect(Rails.logger).to receive(:error).with(/\[Positions::Manager\] Error: .*Boom/)
      expect { described_class.call }.not_to raise_error
    end
  end

  context 'when after EOD, skips exit' do
    before do
      allow(Time).to receive(:current).and_return(Time.zone.local(2024, 1, 1, 15, 16)) # After 15:15
      stub_dhan_positions([valid_position])
    end

    it 'logs skip and does not call Orders::Manager' do
      expect(Rails.logger).to receive(:info).with(/\[Positions::Manager\] Skipped/)
      expect(Orders::Manager).not_to receive(:call)
      described_class.call
    end
  end
end
