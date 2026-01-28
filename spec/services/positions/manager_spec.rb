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
    Rails.cache.clear
    allow(Rails.logger).to receive(:error)
    allow(Rails.logger).to receive(:info)
    allow(Orders::Analyzer).to receive(:call).and_return({ dummy: :data })
    allow(Orders::Manager).to receive(:call)
    allow(Time).to receive(:current).and_return(Time.zone.local(2024, 1, 1, 14, 0))
  end

  def stub_position_models(positions)
    position_objects = positions.map { |p| double('Position', attributes: p) }
    allow(DhanHQ::Models::Position).to receive(:all).and_return(position_objects)
  end

  context 'with mixed valid/invalid positions' do
    before do
      # valid_position has unrealizedProfit 1500, netQty 75, buyAvg 100 → estimate_ltp yields 120
      stub_position_models([valid_position, invalid_position])
    end

    it 'calls Orders::Manager only for valid positions' do
      described_class.call

      expect(Orders::Analyzer).to have_received(:call).with(hash_including(
        'netQty' => 75,
        'buyAvg' => 100,
        'securityId' => 'OPT1',
        'ltp' => 120.0
      ))
      expect(Orders::Manager).to have_received(:call).with(hash_including(
        'netQty' => 75,
        'buyAvg' => 100,
        'securityId' => 'OPT1',
        'ltp' => 120.0
      ), { dummy: :data })
      expect(Orders::Manager).not_to have_received(:call).with(invalid_position, anything)
    end
  end

  context 'when all positions are invalid' do
    before { stub_position_models([invalid_position]) }

    it 'does not call Orders::Manager or Analyzer' do
      expect(Orders::Analyzer).not_to receive(:call)
      expect(Orders::Manager).not_to receive(:call)
      described_class.call
    end
  end

  context 'when positions are empty' do
    before { stub_position_models([]) }

    it 'does not call Orders::Manager or Analyzer' do
      expect(Orders::Analyzer).not_to receive(:call)
      expect(Orders::Manager).not_to receive(:call)
      described_class.call
    end
  end

  context 'when Orders::Manager raises an error' do
    before do
      stub_position_models([valid_position])
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
      allow(Time).to receive(:current).and_return(Time.zone.local(2024, 1, 1, 15, 16))
      stub_position_models([valid_position])
    end

    it 'logs skip and does not call Orders::Manager' do
      expect(Rails.logger).to receive(:info).with(/\[Positions::Manager\] Skipped/)
      expect(Orders::Manager).not_to receive(:call)
      described_class.call
    end
  end
end
