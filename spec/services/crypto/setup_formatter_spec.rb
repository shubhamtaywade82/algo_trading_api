# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Crypto::SetupFormatter do
  subject(:message) { described_class.call(setup) }

  let(:setup) do
    Crypto::Setup.new(
      symbol: 'SOLUSDT', direction: :long, score: 78.5, entry: 152.345, stop: 148.9,
      targets: [162.5, 171.0], risk: 3.445, risk_reward: 2.95,
      confluences: [
        { key: :daily_alignment, weight: 15, label: '1d structure bullish' },
        { key: :m5_trigger, weight: 15, label: '5m BOS through 151.900' }
      ],
      context: { bias: { '1d' => :bullish, '4h' => :bullish, '1h' => :bullish,
                         '15m' => :bullish, '5m' => :bullish },
                 range_zone: :discount }
    )
  end

  it 'leads with the side, the pair and the grade' do
    expect(message).to include('🟢 LONG', 'SOLUSDT', 'grade A', 'score 78.5/100')
  end

  it 'states every level the trade needs' do
    expect(message).to include('Entry   152.345', 'Stop    148.900', 'TP1     162.500', 'TP2     171.000')
    expect(message).to include('R:R 2.95')
  end

  it 'shows the move to each level as a percentage' do
    expect(message).to match(/Stop.*-2\.26%/)
    expect(message).to match(/TP1.*6\.67%/)
  end

  it 'renders the multi-timeframe bias' do
    expect(message).to include('1d ↑', '4h ↑', '5m ↑', 'Range: discount')
  end

  it 'lists the confluences that justified the alert' do
    expect(message).to include('1d structure bullish', '5m BOS through 151.900')
  end

  it 'says plainly that nothing was traded' do
    expect(message).to include('Analysis only — no order was placed.')
  end

  it 'fits inside a single Telegram message' do
    expect(message.length).to be < TelegramNotifier::MAX_LEN
  end

  context 'with a short' do
    let(:setup) do
      Crypto::Setup.new(
        symbol: 'ETHUSDT', direction: :short, score: 66.0, entry: 3400.0, stop: 3450.0,
        targets: [3300.0, 3250.0], risk: 50.0, risk_reward: 2.0, confluences: []
      )
    end

    it 'flips the marker' do
      expect(message).to include('🔴 SHORT', 'ETHUSDT')
    end
  end
end
