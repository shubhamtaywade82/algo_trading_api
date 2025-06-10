# spec/services/scanners/swing_screener_service_spec.rb
require 'rails_helper'

RSpec.describe Scanners::SwingScreenerService do
  subject { described_class.new(limit: 2) }

  let!(:instruments) do
    [
      create(:instrument, symbol_name: 'RELIANCE', exchange: :nse, segment: :equity, security_id: '1594'),
      create(:instrument, symbol_name: 'ICICIBANK', exchange: :nse, segment: :equity, security_id: '1570')
    ]
  end

  # === Shared Setup Variables ===
  let(:last_close)     { 102 }
  let(:last_high)      { 101 }
  let(:last_low)       { 100 }
  let(:last_volume)    { 200_000 }
  let(:avg_volume)     { 100_000 }

  let(:ema_last)       { 100 }
  let(:rsi_last)       { 60 }

  # === Mock Candle Data ===
  let(:mock_ohlc_data) do
    base_price = 90

    candles = (1..250).map do |i|
      {
        date: (Time.zone.today - i).strftime('%Y-%m-%d'),
        open: base_price,
        high: 98,
        low: base_price - 2,
        close: base_price,
        volume: avg_volume
      }
    end

    candles[-1] = {
      date: Time.zone.today.strftime('%Y-%m-%d'),
      open: last_close,
      high: last_high,
      low: last_low,
      close: last_close,
      volume: last_volume
    }

    {
      'close' => candles.pluck(:close),
      'high' => candles.pluck(:high),
      'low' => candles.pluck(:low),
      'open' => candles.pluck(:open),
      'volume' => candles.pluck(:volume),
      'timestamp' => candles.each_index.map { |i| (Time.zone.today - 250 + i).to_time.to_i }
    }
  end

  before do
    allow(Dhanhq::API::Historical).to receive(:daily).and_return(mock_ohlc_data)
    allow(Talib).to receive_messages(ema: Array.new(Scanners::SwingScreenerService::EMA_PERIOD, 90) + [ema_last],
                                     rsi: Array.new(Scanners::SwingScreenerService::RSI_PERIOD,
                                                    60) + [rsi_last])
    allow(Openai::SwingExplainer).to receive(:explain).and_return('AI: good setup')
    allow(TelegramNotifier).to receive(:send_message).and_return(true)
  end

  describe '#call' do
    it 'calls DhanHQ OHLC API for each instrument' do
      expect(Dhanhq::API::Historical).to receive(:daily).twice
      subject.call
    end

    it 'creates SwingPick records for breakout setups' do
      expect { subject.call }.to change(SwingPick, :count).by_at_least(1)
    end

    context 'when price is near low and RSI is oversold' do
      let(:last_close)  { 83 } # ✅ lower than low20 (84)
      let(:last_high)   { 90 }
      let(:last_low)    { 84 }           # <- recent low
      let(:rsi_last)    { 25 }           # ✅
      let(:ema_last)    { 80 }           # ✅ price > ema
      let(:last_volume) { 120_000 }      # ✅
      let(:avg_volume)  { 100_000 }      # ✅

      it 'creates a reversal SwingPick record' do
        expect { subject.call }.to change(SwingPick, :count).by_at_least(1)
        expect(SwingPick.last.setup_type).to eq('reversal')
      end
    end

    context 'when price is below EMA and no breakout or reversal' do
      let(:last_close)  { 85 }
      let(:last_high)   { 100 }
      let(:rsi_last)    { 45 }
      let(:ema_last)    { 100 }

      it 'skips the instrument' do
        expect { subject.call }.not_to(change(SwingPick, :count))
      end
    end

    it 'calls OpenAI explainer for each selected stock' do
      expect(Openai::SwingExplainer).to receive(:explain).at_least(:once)
      subject.call
    end

    it 'stores explanation in the pick' do
      subject.call
      expect(SwingPick.last.analysis).to include('AI:')
    end

    it 'skips instruments with missing candle data' do
      allow(Dhanhq::API::Historical).to receive(:daily).and_return([])
      expect { subject.call }.not_to(change(SwingPick, :count))
    end

    it 'handles and logs DhanHQ failures gracefully' do
      allow(Dhanhq::API::Historical).to receive(:daily).and_raise(StandardError.new('API error'))
      expect { subject.call }.not_to raise_error
    end
  end
end
