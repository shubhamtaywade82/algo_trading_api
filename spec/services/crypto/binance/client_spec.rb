# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Crypto::Binance::Client do
  subject(:client) { described_class.new }

  let(:base) { 'https://fapi.binance.com' }

  describe '#normalize_symbol' do
    it 'accepts the shapes a human or another exchange would write' do
      expect(client.normalize_symbol('solusdt')).to eq('SOLUSDT')
      expect(client.normalize_symbol('SOL/USDT')).to eq('SOLUSDT')
      expect(client.normalize_symbol('SOL-USDT')).to eq('SOLUSDT')
      expect(client.normalize_symbol('eth_usdt')).to eq('ETHUSDT')
    end
  end

  describe '#klines' do
    it 'requests the public endpoint with no credentials attached' do
      stub = stub_request(:get, "#{base}/fapi/v1/klines")
        .with(query: { symbol: 'SOLUSDT', interval: '15m', limit: '200' })
        .to_return(status: 200, body: binance_rows([[100, 101, 99, 100]]).to_json)

      client.klines(symbol: 'sol/usdt', interval: '15m', limit: 200)

      expect(stub).to have_been_requested
      expect(a_request(:get, %r{fapi/v1/klines}).with(headers: { 'X-MBX-APIKEY' => /.*/ })).not_to have_been_made
    end

    it 'caps the limit at what Binance accepts' do
      stub = stub_request(:get, "#{base}/fapi/v1/klines")
        .with(query: hash_including(limit: '1500'))
        .to_return(status: 200, body: '[]')

      client.klines(symbol: 'SOLUSDT', interval: '5m', limit: 99_999)

      expect(stub).to have_been_requested
    end

    it 'raises a typed error on an API rejection' do
      stub_request(:get, "#{base}/fapi/v1/klines")
        .with(query: hash_including({}))
        .to_return(status: 400, body: '{"code":-1121,"msg":"Invalid symbol."}')

      expect { client.klines(symbol: 'NOPEUSDT', interval: '5m') }
        .to raise_error(Crypto::Binance::Error, /responded 400/)
    end

    it 'does not retry an API rejection, which would fail identically' do
      stub = stub_request(:get, "#{base}/fapi/v1/klines")
        .with(query: hash_including({}))
        .to_return(status: 451, body: 'restricted')

      expect { client.klines(symbol: 'SOLUSDT', interval: '5m') }.to raise_error(Crypto::Binance::Error)
      expect(stub).to have_been_requested.once
    end

    it 'retries a transport fault and succeeds on a later attempt' do
      stub_request(:get, "#{base}/fapi/v1/klines")
        .with(query: hash_including({}))
        .to_timeout.then
        .to_return(status: 200, body: binance_rows([[100, 101, 99, 100]]).to_json)

      expect(client.klines(symbol: 'SOLUSDT', interval: '5m').size).to eq(1)
    end
  end

  describe '#series' do
    it 'returns a Series built from the raw rows' do
      stub_request(:get, "#{base}/fapi/v1/klines")
        .with(query: hash_including({}))
        .to_return(status: 200, body: binance_rows([[100, 101, 99, 100], [100, 104, 100, 103]]).to_json)

      series = client.series(symbol: 'SOLUSDT', interval: '5m', limit: 2)

      expect(series).to be_a(Crypto::Series)
      expect(series.size).to eq(2)
      expect(series.last_price).to eq(103.0)
      expect(series.timeframe).to eq('5m')
    end
  end

  describe '#last_price' do
    it 'reads the ticker endpoint' do
      stub_request(:get, "#{base}/fapi/v1/ticker/price")
        .with(query: { symbol: 'ETHUSDT' })
        .to_return(status: 200, body: '{"symbol":"ETHUSDT","price":"3421.55"}')

      expect(client.last_price('ETHUSDT')).to eq(3421.55)
    end
  end

  describe 'base url override' do
    it 'honours CRYPTO_BINANCE_BASE so a restricted region can point elsewhere' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('CRYPTO_BINANCE_BASE').and_return('https://testnet.binancefuture.com')

      stub = stub_request(:get, 'https://testnet.binancefuture.com/fapi/v1/klines')
        .with(query: hash_including({}))
        .to_return(status: 200, body: '[]')

      described_class.new.klines(symbol: 'SOLUSDT', interval: '5m')

      expect(stub).to have_been_requested
    end
  end
end
