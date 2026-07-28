# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Crypto::Healthcheck do
  let(:rows) do
    [
      [1_700_000_000_000, '150.0', '151.0', '149.0', '150.5', '100', 1_700_000_299_999],
      [1_700_000_300_000, '150.5', '152.0', '150.1', '151.75', '120', 1_700_000_599_999]
    ]
  end

  let(:client) do
    instance_double(Crypto::Binance::Client, ping: true, klines: rows, base_urls: %w[https://fapi.binance.com])
  end

  before do
    described_class.reset!
    Rails.cache.clear
    allow(TelegramNotifier).to receive(:send_message)
    allow(Crypto::Config).to receive(:telegram_chat_id).and_return('-100123')
  end

  describe '#call' do
    it 'reports the last close from the candles it actually received' do
      result = described_class.call(client: client, symbol: 'SOLUSDT')

      expect(result).to be_ok
      expect(result.price).to eq(151.75)
      expect(result.candles).to eq(2)
      expect(result.symbol).to eq('SOLUSDT')
    end

    it 'probes the execution timeframe' do
      described_class.call(client: client, symbol: 'SOLUSDT')

      expect(client).to have_received(:klines).with(
        symbol: 'SOLUSDT', interval: Crypto::Config::EXECUTION_TIMEFRAME, limit: 2
      )
    end

    it 'treats a reachable host that returns nothing as down' do
      allow(client).to receive(:klines).and_return([])

      expect(described_class.call(client: client)).not_to be_ok
    end

    it 'carries the HTTP status through so a geo-block is identifiable' do
      allow(client).to receive(:klines)
        .and_raise(Crypto::Binance::Error.new('responded 451', status: 451))

      result = described_class.call(client: client)

      expect(result).not_to be_ok
      expect(result).to be_restricted_region
    end

    it 'identifies a geo-block raised as GeoblockedError, once every mirror has failed' do
      allow(client).to receive(:klines).and_raise(Crypto::Binance::GeoblockedError, 'Datacenter IP is geoblocked.')

      expect(described_class.call(client: client)).to be_restricted_region
    end

    it 'names the mirror pool it tried rather than claiming one host served it' do
      allow(client).to receive(:base_urls).and_return(
        %w[https://fapi.binance.com https://fapi1.binance.com https://fapi2.binance.com]
      )

      expect(described_class.call(client: client).base_url).to eq('https://fapi.binance.com (+2 mirrors)')
    end

    it 'does not let an unexpected failure escape' do
      allow(client).to receive(:ping).and_raise(SocketError, 'no dns')

      expect { described_class.call(client: client) }.not_to raise_error
    end
  end

  describe '.report' do
    it 'announces the first time it sees a healthy connection' do
      described_class.report(client: client)

      expect(TelegramNotifier).to have_received(:send_message).with(
        a_string_including('✅ Binance connected', '151.750'), chat_id: '-100123'
      )
    end

    it 'stays quiet while the state is unchanged' do
      described_class.report(client: client)
      described_class.report(client: client)

      expect(TelegramNotifier).to have_received(:send_message).once
    end

    it 'announces again when asked to, regardless of state' do
      described_class.report(client: client)
      described_class.report(client: client, force: true)

      expect(TelegramNotifier).to have_received(:send_message).twice
    end

    it 'announces the transition to down, and explains a 451' do
      described_class.report(client: client)
      allow(client).to receive(:klines)
        .and_raise(Crypto::Binance::Error.new('Binance /fapi/v1/klines responded 451', status: 451))

      described_class.report(client: client)

      expect(TelegramNotifier).to have_received(:send_message).with(
        a_string_including('🚨 Binance data unavailable', 'geo-block', 'CRYPTO_BINANCE_BASE'),
        chat_id: '-100123'
      )
    end

    it 'does not repeat itself while the outage continues' do
      allow(client).to receive(:klines).and_raise(Crypto::Binance::Error.new('down', status: 503))

      described_class.report(client: client)
      described_class.report(client: client)

      expect(TelegramNotifier).to have_received(:send_message).once
    end

    it 'says so when the data comes back' do
      allow(client).to receive(:klines).and_raise(Crypto::Binance::Error.new('down', status: 503))
      described_class.report(client: client)

      allow(client).to receive(:klines).and_return(rows)
      described_class.report(client: client)

      expect(TelegramNotifier).to have_received(:send_message).with(
        a_string_including('✅ Binance data restored'), chat_id: '-100123'
      )
    end

    it 'honours the alert switch while still returning the result' do
      allow(Crypto::Config).to receive(:health_alerts?).and_return(false)

      expect(described_class.report(client: client)).to be_ok
      expect(TelegramNotifier).not_to have_received(:send_message)
    end

    it 'reports down rather than raising at the caller it was meant to protect' do
      allow(client).to receive(:ping).and_raise(Timeout::Error, 'gave up')

      result = nil
      expect { result = described_class.report(client: client) }.not_to raise_error
      expect(result).not_to be_ok
    end
  end
end
