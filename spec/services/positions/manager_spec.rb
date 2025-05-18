# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Positions::Manager, type: :service do
  let(:valid_position) do
    { 'netQty' => 75, 'buyAvg' => 100, 'ltp' => 120, 'securityId' => 'OPT1', 'exchangeSegment' => 'NSEFO',
      'productType' => 'INTRADAY', 'tradingSymbol' => 'NIFTY24JUL17500CE' }
  end
  let(:invalid_position) do
    { 'netQty' => 0, 'buyAvg' => 0, 'ltp' => 0, 'securityId' => 'OPT2', 'exchangeSegment' => 'NSEFO',
      'productType' => 'INTRADAY', 'tradingSymbol' => 'NIFTY24JUL17600CE' }
  end

  before do
    # By default, stub Analyzer to avoid calling actual code
    allow(Orders::Analyzer).to receive(:call).and_return({ dummy: :data })
  end

  context 'with mixed valid/invalid positions' do
    before { allow(Dhanhq::API::Portfolio).to receive(:positions).and_return([valid_position, invalid_position]) }

    it 'calls Orders::Manager only for valid positions' do
      expect(Orders::Analyzer).to receive(:call).with(valid_position).and_return({ dummy: :data })
      expect(Orders::Manager).to receive(:call).with(valid_position, { dummy: :data })
      expect(Orders::Manager).not_to receive(:call).with(invalid_position, anything)
      described_class.call
    end
  end

  context 'when all positions are invalid' do
    before { allow(Dhanhq::API::Portfolio).to receive(:positions).and_return([invalid_position]) }

    it 'does not call Orders::Manager' do
      expect(Orders::Analyzer).not_to receive(:call)
      expect(Orders::Manager).not_to receive(:call)
      described_class.call
    end
  end

  context 'when positions are empty' do
    before { allow(Dhanhq::API::Portfolio).to receive(:positions).and_return([]) }

    it 'does not call Orders::Manager' do
      expect(Orders::Analyzer).not_to receive(:call)
      expect(Orders::Manager).not_to receive(:call)
      described_class.call
    end
  end

  context 'when Orders::Manager raises an error' do
    before do
      allow(Dhanhq::API::Portfolio).to receive(:positions).and_return([valid_position])
      allow(Orders::Analyzer).to receive(:call).and_return({ dummy: :data })
      allow(Orders::Manager).to receive(:call).and_raise(StandardError, 'Boom')
    end

    it 'rescues and logs error' do
      expect(Rails.logger).to receive(:error).with(/\[Positions::Manager\] Error: Boom/)
      expect { described_class.call }.not_to raise_error
    end
  end

  context 'when after EOD, skips exit' do
    before { allow(Time).to receive(:current).and_return(Time.zone.local(2024, 1, 1, 15, 16)) }

    it 'logs skip and does not call Orders::Manager' do
      allow(Dhanhq::API::Portfolio).to receive(:positions).and_return([valid_position])
      expect(Rails.logger).to receive(:info).with(/\[Positions::Manager\] Skipped/)
      expect(Orders::Manager).not_to receive(:call)
      described_class.call
    end
  end
end
