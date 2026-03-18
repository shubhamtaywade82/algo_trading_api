# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mcp::Tools::GetKeyLevels do
  describe '.execute' do
    let(:segment_index) { instance_double(ActiveRecord::Relation) }
    let(:instrument) do
      instance_double(
        Instrument,
        expiry_list: ['2026-03-27']
      )
    end

    let(:day1) { Time.zone.parse('2026-03-17 09:15:00') }
    let(:day2) { Time.zone.parse('2026-03-18 09:15:00') }

    let(:candles) do
      # 8 candles per day -> 16 total, with constant TR so ATR14 is stable.
      first_day = 8.times.map do |i|
        t = day1 + (i * 5).minutes
        Candle.new(ts: t, open: 100, high: 110, low: 90, close: 100, volume: 1)
      end
      second_day = 8.times.map do |i|
        t = day2 + (i * 5).minutes
        Candle.new(ts: t, open: 100, high: 110, low: 90, close: 100, volume: 1)
      end
      first_day + second_day
    end

    before do
      allow(Instrument).to receive(:segment_index).and_return(segment_index)
      allow(segment_index).to receive(:find_by).with(underlying_symbol: 'NIFTY', exchange: 'nse').and_return(instrument)

      candle_series = instance_double('CandleSeries', candles: candles)
      allow(instrument).to receive(:candle_series).and_return(candle_series)
    end

    it 'returns VWAP, PDH/PDL, ATR14 and simple support/resistance' do
      result = described_class.execute('symbol' => 'NIFTY')

      expect(result[:symbol]).to eq('NIFTY')
      expect(result[:expiry]).to eq('2026-03-27')
      expect(result[:vwap]).to eq(100.0)
      expect(result[:pdh]).to eq(110.0)
      expect(result[:pdl]).to eq(90.0)
      expect(result[:atr]).to eq(20.0)
      expect(result[:support]).to eq(90.0)
      expect(result[:resistance]).to eq(110.0)
    end
  end
end

