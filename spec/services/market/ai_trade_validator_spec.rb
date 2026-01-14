# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Market::AiTradeValidator do
  let(:instrument) { 'NIFTY' }
  let(:options_snapshot) do
    {
      atm: {
        strike: 22_400,
        call: { 'last_price' => 118, 'top_ask_price' => 120 },
        put: { 'last_price' => 112, 'top_ask_price' => 114 }
      }
    }
  end

  it 'accepts a valid BUY trade' do
    text = <<~TXT
      Decision: BUY
      Instrument: NIFTY
      Bias: BULLISH
      Option:
      - Type: CE
      - Strike: 22400
      - Expiry: 2026-01-16
      Execution:
      - Entry Premium: 118
      - Stop Loss Premium: 88
      - Target Premium: 178
      - Risk Reward: 2.0
      Underlying Context:
      - Spot Above: 22460
      - Invalidation Below: 22390
      Exit Rules:
      - SL Hit on premium
      - OR Spot closes below 22390 on 5m
      - OR Spot fails to hold above VWAP for 2 consecutive 5m candles
      Reason: 15m BOS with 5m continuation above VWAP.
    TXT

    result = described_class.call!(text, instrument_symbol: instrument, options_snapshot: options_snapshot)

    expect(result.decision).to eq('BUY')
    expect(result.instrument).to eq('NIFTY')
    expect(result.option['Type']).to eq('CE')
    expect(result.option['Strike']).to eq('22400')
  end

  it 'rejects low RR trades' do
    text = <<~TXT
      Decision: BUY
      Instrument: NIFTY
      Bias: BULLISH
      Option:
      - Type: CE
      - Strike: 22400
      - Expiry: 2026-01-16
      Execution:
      - Entry Premium: 118
      - Stop Loss Premium: 112
      - Target Premium: 124
      - Risk Reward: 1.0
      Underlying Context:
      - Spot Above: 22460
      - Invalidation Below: 22390
      Exit Rules:
      - SL Hit on premium
      - OR Spot closes below 22390 on 5m
      Reason: Weak trend.
    TXT

    expect { described_class.call!(text, instrument_symbol: instrument, options_snapshot: options_snapshot) }
      .to raise_error(Market::AiTradeValidator::ValidationError, /RR < 1.5/)
  end

  it 'accepts NO_TRADE with re-evaluation triggers' do
    text = <<~TXT
      Decision: NO_TRADE
      Instrument: NIFTY
      Market Bias: UNCLEAR
      Reason: Price inside 15m AVRZ and conflicting 5m structure.
      Risk Note: No edge for options buying
      Re-evaluate When:
      - 15m BOS above 22480
      - Breakdown below 22320
    TXT

    result = described_class.call!(text, instrument_symbol: instrument, options_snapshot: options_snapshot)
    expect(result.decision).to eq('NO_TRADE')
  end
end

