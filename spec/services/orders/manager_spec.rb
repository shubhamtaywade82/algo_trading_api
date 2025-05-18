# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Orders::Manager, type: :service do
  let(:position) do
    {
      'tradingSymbol' => 'NIFTY24JUL17500CE',
      'securityId' => 'OPT123',
      'exchangeSegment' => 'NSEFO',
      'buyAvg' => 100,
      'netQty' => 75,
      'ltp' => 110
    }
  end
  let(:analysis) { { entry_price: 100, ltp: 110, pnl: 750, pnl_pct: 10.0, quantity: 75, instrument_type: :option } }

  context 'when risk manager decides to exit' do
    before do
      allow(Orders::RiskManager).to receive(:call).and_return({ exit: true, exit_reason: 'TP', adjust: false })
      allow(Orders::Executor).to receive(:call)
    end

    it 'calls Orders::Executor with correct args' do
      expect(Orders::Executor).to receive(:call).with(position, 'TP', analysis)

      described_class.call(position, analysis)
    end
  end

  context 'when risk manager decides to adjust' do
    let(:adjust_params) { { trigger_price: 105.0 } }

    before do
      allow(Orders::RiskManager).to receive(:call).and_return({ exit: false, adjust: true,
                                                                adjust_params: adjust_params })
      allow(Orders::Adjuster).to receive(:call)
    end

    it 'calls Orders::Adjuster with correct args' do
      expect(Orders::Adjuster).to receive(:call).with(position, adjust_params)
      described_class.call(position, analysis)
    end
  end

  context 'when risk manager returns neither exit nor adjust' do
    before do
      allow(Orders::RiskManager).to receive(:call).and_return({ exit: false, adjust: false })
    end

    it 'does not call Executor or Adjuster' do
      expect(Orders::Executor).not_to receive(:call)
      expect(Orders::Adjuster).not_to receive(:call)
      described_class.call(position, analysis)
    end
  end

  context 'when an error occurs' do
    before do
      allow(Orders::RiskManager).to receive(:call).and_raise(StandardError, 'Manager error')
    end

    it 'logs the error and does not raise' do
      expect(Rails.logger).to receive(:error).with(/\[Orders::Manager\] Error for NIFTY24JUL17500CE: Manager error/)
      expect { described_class.call(position, analysis) }.not_to raise_error
    end
  end
end
