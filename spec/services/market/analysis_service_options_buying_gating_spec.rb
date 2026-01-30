# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Market::AnalysisService do
  describe '#call' do
    it 'does not call OpenAI when SMC/AVRZ inputs are missing' do
      service = described_class.new('NIFTY', trade_type: :options_buying)

      series = instance_double(CandleSeries, candles: [double('Candle')])
      instrument = instance_double(Instrument, symbol_name: 'NIFTY', ltp: 20_000, id: 1)
      allow(instrument).to receive(:candle_series).and_return(series)

      md = ActiveSupport::HashWithIndifferentAccess.new(
        symbol: 'NIFTY',
        ts: Time.current,
        frame: '15m',
        expiry: '2026-01-15',
        ltp: 20_000,
        session: :live,
        ohlc: { open: 1, high: 1, low: 1, close: 1, volume: 0 },
        prev_day: nil,
        boll: {},
        atr: 1,
        rsi: 1,
        macd: { macd: 0, signal: 0, hist: 0 },
        ema14: 1,
        super: :bullish,
        hi20: 1,
        lo20: 1,
        liq_up: false,
        liq_dn: false,
        options: nil
      )

      allow(service).to receive_messages(
        instrument: instrument,
        india_vix: instance_double(Instrument, ltp: 12),
        build_market_snapshot: md,
        option_chain_regime_flags: {},
        enrich_with_structure_and_value!: nil,
        sleep: nil
      )

      expect(Openai::ChatRouter).not_to receive(:ask!)

      result = service.call
      expect(result).to eq('⚠️ No valid trade setup found.')
    end
  end
end

