# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Market::AiTradeValidator do
  let(:ltp) { 120 }

  it 'accepts a valid BUY trade' do
    text = <<~TXT
      Decision: BUY
      Instrument: NIFTY
      Side: CE
      Strike: 22400
      Entry: 120
      Stop Loss: 100
      Target: 170
      Risk Reward: 2.5
      Reason: Bullish BOS with support above VWAP.
    TXT

    result = described_class.call!(text, ltp: ltp)

    expect(result.decision).to eq('BUY')
    expect(result.instrument).to eq('NIFTY')
    expect(result.side).to eq('CE')
    expect(result.strike).to eq(22_400)
  end

  it 'rejects low RR trades' do
    text = <<~TXT
      Decision: BUY
      Instrument: NIFTY
      Side: CE
      Strike: 22400
      Entry: 120
      Stop Loss: 110
      Target: 130
      Risk Reward: 1.1
      Reason: Weak trend.
    TXT

    expect { described_class.call!(text, ltp: ltp) }
      .to raise_error(Market::AiTradeValidator::ValidationError, /RR < 1.5/)
  end

  it 'rejects missing fields' do
    text = <<~TXT
      Decision: BUY
      Instrument: NIFTY
      Side: CE
      Strike: 22400
      Entry: 120
    TXT

    expect { described_class.call!(text, ltp: ltp) }
      .to raise_error(Market::AiTradeValidator::ValidationError, /Missing fields/)
  end
end

