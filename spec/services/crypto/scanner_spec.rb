# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Crypto::Scanner do
  let(:setup) do
    Crypto::Setup.new(symbol: 'SOLUSDT', direction: :long, score: 80.0, entry: 100.0, stop: 97.0,
                      targets: [106.0, 112.0], risk: 3.0, risk_reward: 2.0, confluences: [])
  end

  let(:analyzer) { instance_double(Crypto::Analyzer) }

  before do
    allow(Crypto::Analyzer).to receive(:new).and_return(analyzer)
    allow(Crypto::AlertDispatcher).to receive(:dispatch).and_return(:sent)
  end

  it 'returns nothing when no symbol produces a setup' do
    allow(analyzer).to receive(:call).and_return(nil)

    expect(described_class.call(symbols: %w[SOLUSDT ETHUSDT])).to be_empty
    expect(Crypto::AlertDispatcher).not_to have_received(:dispatch)
  end

  it 'dispatches each setup it finds' do
    allow(analyzer).to receive(:call).and_return(setup)

    results = described_class.call(symbols: %w[SOLUSDT])

    expect(results.size).to eq(1)
    expect(results.first).to be_alerted
    expect(Crypto::AlertDispatcher).to have_received(:dispatch).with(setup)
  end

  it 'can analyse without notifying' do
    allow(analyzer).to receive(:call).and_return(setup)

    results = described_class.call(symbols: %w[SOLUSDT], notify: false)

    expect(results.first.status).to eq(:skipped)
    expect(Crypto::AlertDispatcher).not_to have_received(:dispatch)
  end

  it 'defaults to the configured symbols' do
    allow(Crypto::Config).to receive(:symbols).and_return(%w[SOLUSDT ETHUSDT])
    allow(analyzer).to receive(:call).and_return(nil)

    described_class.call

    expect(Crypto::Analyzer).to have_received(:new).twice
  end

  it 'carries on with the next symbol when one blows up' do
    allow(analyzer).to receive(:call).and_raise(StandardError, 'boom')

    expect { described_class.call(symbols: %w[SOLUSDT ETHUSDT]) }.not_to raise_error
  end
end
