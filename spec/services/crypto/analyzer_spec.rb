# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Crypto::Analyzer do
  let(:base) { 'https://fapi.binance.com' }

  def stub_klines(bars)
    stub_request(:get, "#{base}/fapi/v1/klines")
      .with(query: hash_including({}))
      .to_return(status: 200, body: binance_rows(bars).to_json)
  end

  it 'normalises the symbol before requesting anything' do
    stub_klines(zigzag_bars(legs: 12))

    expect(described_class.new('sol/usdt').symbol).to eq('SOLUSDT')
  end

  it 'builds a report for every configured timeframe' do
    stub_klines(zigzag_bars(legs: 14))

    reports = described_class.new('SOLUSDT').reports

    expect(reports.keys).to match_array(Crypto::Config::TIMEFRAMES)
    expect(reports.values).to all(be_a(Crypto::Smc::TimeframeReport))
  end

  it 'returns nil rather than half a picture when a timeframe fails' do
    stub_request(:get, "#{base}/fapi/v1/klines")
      .with(query: hash_including({}))
      .to_return(status: 451, body: 'restricted')

    expect(described_class.new('SOLUSDT').call).to be_nil
  end

  it 'returns nil when a timeframe comes back too short to analyse' do
    stub_klines(zigzag_bars(legs: 1, step: 4))

    expect(described_class.new('SOLUSDT').call).to be_nil
  end

  it 'hands the reports to the detector and returns its verdict' do
    stub_klines(zigzag_bars(legs: 14))
    allow(Crypto::SetupDetector).to receive(:call).and_return(:a_setup)

    expect(described_class.new('SOLUSDT').call).to eq(:a_setup)
    expect(Crypto::SetupDetector).to have_received(:call)
      .with(hash_including(symbol: 'SOLUSDT'))
  end

  it 'never places an order — the client has no signed request path' do
    expect(Crypto::Binance::Client.instance_methods).not_to include(:place_order, :sign, :signed_request)
  end
end
