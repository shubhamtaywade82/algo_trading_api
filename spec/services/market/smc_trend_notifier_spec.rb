# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Market::SmcTrendNotifier do
  let(:cache_key) { described_class::CACHE_KEY }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('TELEGRAM_CHAT_ID').and_return('123')
    allow(ENV).to receive(:[]).with('ENABLE_SMC_TREND_NOTIFY').and_return('true')
    allow(Rails.cache).to receive(:read).with(cache_key).and_return(nil)
    allow(Rails.cache).to receive(:write)
    allow(TelegramNotifier).to receive(:send_message)
  end

  describe '#call' do
    context 'when TELEGRAM_CHAT_ID is blank' do
      before { allow(ENV).to receive(:[]).with('TELEGRAM_CHAT_ID').and_return(nil) }

      it 'does not send a message' do
        described_class.new('NIFTY' => build_candles(50)).call

        expect(TelegramNotifier).not_to have_received(:send_message)
      end
    end

    context 'when ENABLE_SMC_TREND_NOTIFY is not true' do
      before { allow(ENV).to receive(:[]).with('ENABLE_SMC_TREND_NOTIFY').and_return('false') }

      it 'does not send a message' do
        described_class.new('NIFTY' => build_candles(50)).call

        expect(TelegramNotifier).not_to have_received(:send_message)
      end
    end

    context 'when candle_map is empty' do
      it 'does not send a message' do
        described_class.new({}).call

        expect(TelegramNotifier).not_to have_received(:send_message)
      end
    end

    context 'when cooldown is active' do
      before { allow(Rails.cache).to receive(:read).with(cache_key).and_return(Time.current.to_i) }

      it 'does not send a message' do
        described_class.new('NIFTY' => build_candles(50)).call

        expect(TelegramNotifier).not_to have_received(:send_message)
      end
    end

    context 'when BANKNIFTY is in candle_map but next expiry is beyond 7 days' do
      let(:banknifty_inst) { instance_double(Instrument, expiry_list: [Time.zone.today + 10]) }
      let(:analyzer_result) do
        {
          smc: {
            structure_bias: :bullish,
            swing_highs: [25_100, 25_200],
            swing_lows: [24_900, 25_000],
            fvg_bullish: nil, fvg_bearish: nil,
            order_block_bullish: nil, order_block_bearish: nil
          },
          price_action: {}
        }
      end
      let(:analyzer_double) { instance_double(Market::SmcPriceActionAnalyzer, call: analyzer_result) }
      let(:sent_messages) { [] }

      before do
        allow(Instrument).to receive(:find_by).with(underlying_symbol: 'BANKNIFTY', segment: 'index').and_return(banknifty_inst)
        allow(Instrument).to receive(:find_by).with(anything, anything).and_call_original
        allow(Market::SmcPriceActionAnalyzer).to receive(:new).and_return(analyzer_double)
        allow(TelegramNotifier).to receive(:send_message) { |msg, **_| sent_messages << msg }
      end

      it 'excludes BANKNIFTY from the notification' do
        candles = build_candles(55)
        candle_map = { 'NIFTY' => candles, 'SENSEX' => candles, 'BANKNIFTY' => candles }

        described_class.new(candle_map).call

        expect(TelegramNotifier).to have_received(:send_message).once
        expect(sent_messages.last).not_to include('BANKNIFTY')
      end
    end

    context 'when no symbol triggers (no BOS, no level touch)' do
      let(:neutral_analyzer_result) do
        {
          smc: {
            structure_bias: :neutral,
            swing_highs: [],
            swing_lows: [],
            fvg_bullish: nil,
            fvg_bearish: nil,
            order_block_bullish: nil,
            order_block_bearish: nil
          },
          price_action: {}
        }
      end
      let(:neutral_analyzer_double) { instance_double(Market::SmcPriceActionAnalyzer, call: neutral_analyzer_result) }

      it 'does not send a message' do
        allow(Market::SmcPriceActionAnalyzer).to receive(:new).and_return(neutral_analyzer_double)
        candles = build_candles(55)
        candle_map = { 'NIFTY' => candles, 'SENSEX' => candles }

        described_class.new(candle_map).call

        expect(TelegramNotifier).not_to have_received(:send_message)
      end
    end
  end

  def build_candles(count, flat: false)
    base = 25_000.0
    (1..count).map do |i|
      c = flat ? base : base + (i * 2) + (i % 3)
      {
        open: c - 5, high: c + 5, low: c - 8, close: c,
        timestamp: Time.current - (count - i).minutes,
        volume: 1000
      }
    end
  end
end
