# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Crypto::SmcScanJob do
  before { allow(Crypto::Scanner).to receive(:call).and_return([]) }

  context 'when the scanner is disabled' do
    before { allow(Crypto::Config).to receive(:enabled?).and_return(false) }

    it 'does nothing at all' do
      described_class.perform_now

      expect(Crypto::Scanner).not_to have_received(:call)
    end
  end

  context 'when the scanner is enabled' do
    before { allow(Crypto::Config).to receive(:enabled?).and_return(true) }

    it 'scans every configured symbol by default' do
      described_class.perform_now

      expect(Crypto::Scanner).to have_received(:call).with(symbols: nil)
    end

    it 'scans only the symbols it was given' do
      described_class.perform_now(%w[SOLUSDT])

      expect(Crypto::Scanner).to have_received(:call).with(symbols: %w[SOLUSDT])
    end

    it 'accepts a bare symbol' do
      described_class.perform_now('ETHUSDT')

      expect(Crypto::Scanner).to have_received(:call).with(symbols: %w[ETHUSDT])
    end

    it 'discards a failed scan instead of retrying it onto a stale candle' do
      allow(Crypto::Scanner).to receive(:call).and_raise(StandardError, 'binance down')

      expect { described_class.perform_now }.not_to raise_error
    end
  end

  it 'does not inherit the DhanHQ token check that guards ApplicationJob' do
    # Binance market data needs no credential, and a lapsed Dhan session must
    # not take the crypto scanner down with it.
    expect(described_class.superclass).to eq(ActiveJob::Base)
    expect(described_class.ancestors).not_to include(ApplicationJob)
  end
end
