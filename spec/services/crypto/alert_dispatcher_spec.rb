# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Crypto::AlertDispatcher do
  let(:poi) do
    Crypto::Smc::Zone.new(kind: :order_block, direction: :bullish, top: 99.0, bottom: 97.5,
                          index: 50, time: Time.current)
  end

  def build_setup(symbol: 'SOLUSDT', direction: :long, poi_zone: poi)
    Crypto::Setup.new(
      symbol: symbol, direction: direction, score: 80.0, entry: 100.0, stop: 97.2,
      targets: [108.0, 115.0], risk: 2.8, risk_reward: 2.86,
      confluences: [{ key: :m5_trigger, weight: 15, label: '5m BOS' }], poi: poi_zone
    )
  end

  before do
    described_class.reset!
    allow(TelegramNotifier).to receive(:send_message)
    allow(Crypto::Config).to receive(:telegram_chat_id).and_return('-100123')
    allow(Crypto::Analyst).to receive(:call).and_return(nil)
  end

  it 'sends the formatted setup to the configured chat' do
    expect(described_class.dispatch(build_setup)).to eq(:sent)
    expect(TelegramNotifier).to have_received(:send_message).with(
      a_string_including('LONG', 'SOLUSDT'), chat_id: '-100123'
    )
  end

  it 'includes the execution plan when the analyst produced one' do
    allow(Crypto::Analyst).to receive(:call).and_return('ENTRY: limit into the block.')

    described_class.dispatch(build_setup)

    expect(TelegramNotifier).to have_received(:send_message).with(
      a_string_including('🤖 Execution plan', 'ENTRY: limit into the block.'), chat_id: '-100123'
    )
  end

  it 'sends the levels anyway when the analyst could not answer' do
    allow(Crypto::Analyst).to receive(:call).and_return(nil)

    expect(described_class.dispatch(build_setup)).to eq(:sent)
    expect(TelegramNotifier).to have_received(:send_message).with(
      a_string_including('Entry'), chat_id: '-100123'
    )
  end

  it 'does not pay for a plan on a setup it is going to suppress' do
    described_class.dispatch(build_setup)
    described_class.dispatch(build_setup)

    expect(Crypto::Analyst).to have_received(:call).once
  end

  it 'stays silent the second time the same setup is seen' do
    expect(described_class.dispatch(build_setup)).to eq(:sent)
    expect(described_class.dispatch(build_setup)).to eq(:suppressed)

    expect(TelegramNotifier).to have_received(:send_message).once
  end

  it 'still alerts when the other side of the same pair sets up' do
    described_class.dispatch(build_setup(direction: :long))

    expect(described_class.dispatch(build_setup(direction: :short))).to eq(:sent)
  end

  it 'still alerts for a different pair' do
    described_class.dispatch(build_setup(symbol: 'SOLUSDT'))

    expect(described_class.dispatch(build_setup(symbol: 'ETHUSDT'))).to eq(:sent)
  end

  it 'alerts again once the cooldown has passed' do
    allow(Crypto::Config).to receive(:cooldown_seconds).and_return(60)

    described_class.dispatch(build_setup)

    travel_to(61.seconds.from_now) do
      Rails.cache.clear # the shared half expires on its own TTL
      expect(described_class.dispatch(build_setup)).to eq(:sent)
    end
  end

  it 'suppresses across processes via the shared cooldown' do
    described_class.dispatch(build_setup)
    described_class.reset! # simulate a second process with a cold in-memory store

    expect(described_class.dispatch(build_setup)).to eq(:suppressed)
  end

  it 'reports when no chat is configured rather than raising' do
    allow(Crypto::Config).to receive(:telegram_chat_id).and_return(nil)

    expect(described_class.dispatch(build_setup)).to eq(:unconfigured)
    expect(TelegramNotifier).not_to have_received(:send_message)
  end

  it 'reports a delivery failure without propagating it' do
    allow(TelegramNotifier).to receive(:send_message).and_raise(StandardError, 'telegram down')

    expect(described_class.dispatch(build_setup)).to eq(:failed)
  end

  it 'falls back to the in-process cooldown when the shared cache is unavailable' do
    allow(Rails.cache).to receive(:read).and_raise(StandardError, 'cache down')
    allow(Rails.cache).to receive(:write).and_raise(StandardError, 'cache down')

    expect(described_class.dispatch(build_setup)).to eq(:sent)
    expect(described_class.dispatch(build_setup)).to eq(:suppressed)
  end
end
