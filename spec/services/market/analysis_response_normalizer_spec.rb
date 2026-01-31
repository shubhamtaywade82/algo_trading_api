# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Market::AnalysisResponseNormalizer do
  let(:md) do
    {
      symbol: 'NIFTY',
      ltp: 25_315.8,
      atr: 48.01,
      vix: 13.63,
      super: 'bearish',
      boll: { middle: 25_059.5, upper: 25_535.2, lower: 25_297.3 },
      price_action: { last_candle_bullish: false }
    }
  end

  describe '#call' do
    context 'when response has no CLOSE RANGE and no Bias line' do
      let(:answer) { "AT A GLANCE:\n• Bias: PUTS\n— end of recommendations" }

      it 'appends CLOSE RANGE line from market data' do
        result = described_class.new(answer, md).call

        expect(result).to match(/\bCLOSE RANGE:\s*₹\d+–₹\d+/)
        expect(result).to include('from LTP)')
      end

      it 'appends Bias line when missing' do
        result = described_class.new("Only text.\n— end", md).call

        expect(result).to match(/\bBias:\s*(CALLS|PUTS|NEUTRAL)\b/)
      end
    end

    context 'when response already has CLOSE RANGE and Bias' do
      let(:answer) do
        "AT A GLANCE.\nCLOSE RANGE: ₹25200–₹25450 (−0.46% to +0.53% from LTP)\n\nBias: PUTS"
      end

      it 'does not duplicate CLOSE RANGE or Bias' do
        result = described_class.new(answer, md).call

        expect(result.scan('CLOSE RANGE:').size).to eq(1)
        expect(result.scan(/\bBias:\s*PUTS\b/).size).to eq(1)
      end
    end

    context 'when market data lacks boll/atr/ltp' do
      let(:answer) { 'Text only.' }
      let(:minimal_md) { { symbol: 'NIFTY', super: 'neutral', price_action: {} } }

      it 'returns answer with only Bias appended when CLOSE RANGE cannot be computed' do
        result = described_class.new(answer, minimal_md).call

        expect(result).not_to include('CLOSE RANGE:')
        expect(result).to match(/\bBias:\s*NEUTRAL\b/)
      end
    end

    context 'when response has wrong SL ₹ for stated SL %' do
      let(:answer) do
        "PRIMARY: ATM CE (25300) ₹212.9; SL -8% ⇒ ₹191.61\nCLOSE RANGE: ₹25200–₹25450\nBias: NEUTRAL"
      end

      it 'corrects SL ₹ to entry × (1 − SL%)' do
        result = described_class.new(answer, md).call

        expect(result).to include('SL -8% ⇒ ₹195.87')
        expect(result).not_to include('SL -8% ⇒ ₹191.61')
      end
    end

    context 'when response has wrong T1 ₹ for stated T1 %' do
      let(:answer) do
        "PRIMARY: ATM CE (25300) ₹212.9; T1 +15% ⇒ ₹319.35\nCLOSE RANGE: ₹25200–₹25450\nBias: NEUTRAL"
      end

      it 'corrects T1 ₹ to entry × (1 + T1%)' do
        result = described_class.new(answer, md).call

        expect(result).to include('T1 +15% ⇒ ₹244.84')
        expect(result).not_to include('T1 +15% ⇒ ₹319.35')
      end
    end
  end
end
