# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trading::TradeDecisionEngine, type: :service do
  let(:symbol) { 'NIFTY' }
  let(:expiry) { '2026-03-27' }
  let(:spot) { 22000.0 }

  let(:instrument) { instance_double(Instrument) }

  let(:candles) do
    Array.new(15).each_with_index.map do |_, i|
      c = 22000.0 + (i * 20.0)
      { open: c - 5, high: c + 100, low: c - 100, close: c, volume: 1000 }
    end
  end

  let(:option_chain) do
    {
      last_price: spot,
      oc: {
        '22000.000000' => {
          'ce' => { 'oi' => 100_000, 'implied_volatility' => 0.20 },
          'pe' => { 'oi' => 500_000, 'implied_volatility' => 0.22 }
        }
      }
    }
  end

  let(:regime_result) do
    Trading::RegimeScorer::Result.new(state: :tradeable, trend: :bullish, reason: nil)
  end

  let(:direction_result) do
    Trading::DirectionResolver::Result.new(
      direction: 'CE',
      reason: 'bullish price + bullish OI',
      vwap: 21900.0,
      oi_bias: :bullish,
      price_bias: :bullish
    )
  end

  let(:entry_result) do
    Trading::EntryValidator::Result.new(valid: true, reason: 'Bullish breakout confirmed')
  end

  let(:chain_analysis) do
    {
      proceed: true,
      reason: nil,
      trend: :bullish,
      momentum: :strong,
      adx: 25.0,
      selected: { strike: 22000, option_type: 'CE', score: 0.85 },
      ranked: [{ strike: 22000, option_type: 'CE', score: 0.85 }]
    }
  end

  let(:historical_data) { [] }

  let(:analyzer_double) { instance_double(Option::ChainAnalyzer, analyze: chain_analysis) }

  before do
    allow(Instrument).to receive(:segment_index).and_return(Instrument)
    allow(Instrument).to receive(:find_by).and_return(instrument)

    allow(instrument).to receive(:ltp).and_return(spot)
    allow(instrument).to receive(:expiry_list).and_return([expiry])
    allow(instrument).to receive(:fetch_option_chain).with(expiry).and_return(option_chain)
    allow(instrument).to receive(:intraday_ohlc).with(interval: '5', days: 2).and_return(candles)

    allow(Option::ChainAnalyzer).to receive(:estimate_iv_rank).and_return(0.40) # => 40% iv_rank
    allow(Option::HistoricalDataFetcher).to receive(:for_strategy).and_return(historical_data)
    allow(Option::ChainAnalyzer).to receive(:new).and_return(analyzer_double)

    allow(Trading::RegimeScorer).to receive(:call).and_return(regime_result)
    allow(Trading::DirectionResolver).to receive(:call).and_return(direction_result)
    allow(Trading::EntryValidator).to receive(:call).and_return(entry_result)
  end

  describe '#call' do
    context 'when symbol is not allowed' do
      it 'returns no_trade with unsupported symbol reason' do
        result = described_class.call(symbol: 'RELIANCE', expiry: expiry)
        expect(result.proceed).to be false
        expect(result.reason).to include('not supported')
      end
    end

    context 'when instrument is not found' do
      before do
        allow(Instrument).to receive(:find_by).and_return(nil)
      end

      it 'returns no_trade with instrument not found reason' do
        result = described_class.call(symbol: symbol, expiry: expiry)
        expect(result.proceed).to be false
        expect(result.reason).to include('Instrument not found')
      end
    end

    context 'when insufficient candle data (< 10 candles)' do
      before do
        allow(instrument).to receive(:intraday_ohlc).and_return(Array.new(5) { { open: 22000.0, high: 22100.0, low: 21900.0, close: 22000.0, volume: 100 } })
      end

      it 'returns no_trade with insufficient candle reason' do
        result = described_class.call(symbol: symbol, expiry: expiry)
        expect(result.proceed).to be false
        expect(result.reason).to include('Insufficient candle data')
      end
    end

    context 'when LTP is zero' do
      before do
        allow(instrument).to receive(:ltp).and_return(0)
      end

      it 'returns no_trade with LTP unavailable reason' do
        result = described_class.call(symbol: symbol, expiry: expiry)
        expect(result.proceed).to be false
        expect(result.reason).to include('LTP unavailable')
      end
    end

    context 'when no expiry is available' do
      before do
        allow(instrument).to receive(:expiry_list).and_return([])
      end

      it 'returns no_trade with no expiry reason' do
        result = described_class.call(symbol: symbol, expiry: nil)
        expect(result.proceed).to be false
        expect(result.reason).to include('No expiry available')
      end
    end

    context 'when option chain is unavailable' do
      before do
        allow(instrument).to receive(:fetch_option_chain).and_return(nil)
      end

      it 'returns no_trade with chain unavailable reason' do
        result = described_class.call(symbol: symbol, expiry: expiry)
        expect(result.proceed).to be false
        expect(result.reason).to include('Option chain unavailable')
      end
    end

    context 'when option chain OC is empty' do
      before do
        allow(instrument).to receive(:fetch_option_chain).and_return({ last_price: spot, oc: {} })
      end

      it 'returns no_trade with OC data empty reason' do
        result = described_class.call(symbol: symbol, expiry: expiry)
        expect(result.proceed).to be false
        expect(result.reason).to include('Option chain OC data empty')
      end
    end

    context 'when regime scorer returns no_trade' do
      let(:regime_result) do
        Trading::RegimeScorer::Result.new(state: :no_trade, trend: nil, reason: 'IV rank too low (15.0): no premium')
      end

      it 'returns no_trade with regime reason' do
        result = described_class.call(symbol: symbol, expiry: expiry)
        expect(result.proceed).to be false
        expect(result.reason).to include('IV rank too low')
      end
    end

    context 'when direction resolver returns nil direction' do
      let(:direction_result) do
        Trading::DirectionResolver::Result.new(
          direction: nil,
          reason: 'No confirmation: price=bullish oi=bearish',
          vwap: 21900.0,
          oi_bias: :bearish,
          price_bias: :bullish
        )
      end

      it 'returns no_trade with no directional signal reason' do
        result = described_class.call(symbol: symbol, expiry: expiry)
        expect(result.proceed).to be false
        expect(result.reason).to include('No directional signal')
      end
    end

    context 'when entry validator returns invalid' do
      let(:entry_result) do
        Trading::EntryValidator::Result.new(valid: false, reason: 'No breakout: close 22000 <= prev high 22050')
      end

      it 'returns no_trade with entry not confirmed reason' do
        result = described_class.call(symbol: symbol, expiry: expiry)
        expect(result.proceed).to be false
        expect(result.reason).to include('Entry not confirmed')
      end
    end

    context 'when chain analysis blocks the trade' do
      let(:chain_analysis) do
        { proceed: false, reason: 'IV rank too high for selling', trend: :bullish, momentum: :flat, adx: 15.0, selected: nil, ranked: [] }
      end

      it 'returns no_trade with chain analysis blocked reason' do
        result = described_class.call(symbol: symbol, expiry: expiry)
        expect(result.proceed).to be false
        expect(result.reason).to include('Chain analysis blocked')
      end
    end

    context 'happy path — all gates pass' do
      it 'returns proceed: true with correct fields populated' do
        result = described_class.call(symbol: symbol, expiry: expiry)

        expect(result.proceed).to be true
        expect(result.symbol).to eq('NIFTY')
        expect(result.direction).to eq('CE')
        expect(result.expiry).to eq(expiry)
        expect(result.iv_rank).to eq(40.0)
        expect(result.spot).to eq(spot)
        expect(result.regime).to eq(regime_result)
        expect(result.selected_strike).to be_present
        expect(result.reason).to be_nil
        expect(result.timestamp).to be_present
      end
    end

    context 'SENSEX symbol uses BSE exchange lookup' do
      it 'looks up by BSE exchange' do
        described_class.call(symbol: 'SENSEX', expiry: expiry)
        expect(Instrument).to have_received(:find_by).with(underlying_symbol: 'SENSEX', exchange: 'bse')
      end
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trading::TradeDecisionEngine, type: :service do
  let(:symbol) { 'NIFTY' }
  let(:expiry) { '2026-03-27' }
  let(:spot) { 22000.0 }

  let(:instrument) { instance_double(Instrument) }

  # 15 candles with enough range to pass regime check
  let(:candles) do
    Array.new(15) do |i|
      c = 22000.0 + (i * 20.0)
      { open: c - 5, high: c + 100, low: c - 100, close: c, volume: 1000 }
    end
  end

  # Option chain in DhanHQ format
  let(:option_chain) do
    {
      last_price: spot,
      oc: {
        '22000.000000' => {
          'ce' => { 'oi' => 100_000, 'implied_volatility' => 0.20 },
          'pe' => { 'oi' => 500_000, 'implied_volatility' => 0.22 }
        }
      }
    }
  end

  let(:regime_result) do
    Trading::RegimeScorer::Result.new(state: :tradeable, trend: :bullish, reason: nil)
  end

  let(:direction_result) do
    Trading::DirectionResolver::Result.new(
      direction: 'CE', reason: 'bullish price + bullish OI',
      vwap: 21900.0, oi_bias: :bullish, price_bias: :bullish
    )
  end

  let(:entry_result) do
    Trading::EntryValidator::Result.new(valid: true, reason: 'Bullish breakout confirmed')
  end

  let(:chain_analysis) do
    {
      proceed: true,
      reason: nil,
      trend: :bullish,
      momentum: :strong,
      adx: 25.0,
      selected: { strike: 22000, option_type: 'CE', score: 0.85 },
      ranked: [{ strike: 22000, option_type: 'CE', score: 0.85 }]
    }
  end

  let(:historical_data) { [] }
  let(:analyzer_double) { instance_double(Option::ChainAnalyzer, analyze: chain_analysis) }

  before do
    allow(Instrument).to receive(:segment_index).and_return(Instrument)
    allow(Instrument).to receive(:find_by).and_return(instrument)
    allow(instrument).to receive(:ltp).and_return(spot)
    allow(instrument).to receive(:expiry_list).and_return([expiry])
    allow(instrument).to receive(:fetch_option_chain).with(expiry).and_return(option_chain)
    allow(instrument).to receive(:intraday_ohlc).with(interval: '5', days: 2).and_return(candles)

    allow(Option::ChainAnalyzer).to receive(:estimate_iv_rank).and_return(0.40) # => 40% iv_rank
    allow(Option::HistoricalDataFetcher).to receive(:for_strategy).and_return(historical_data)
    allow(Option::ChainAnalyzer).to receive(:new).and_return(analyzer_double)

    allow(Trading::RegimeScorer).to receive(:call).and_return(regime_result)
    allow(Trading::DirectionResolver).to receive(:call).and_return(direction_result)
    allow(Trading::EntryValidator).to receive(:call).and_return(entry_result)
  end

  describe '#call' do
    context 'when symbol is not in the allowed list' do
      it 'returns no_trade with unsupported symbol reason' do
        result = described_class.call(symbol: 'RELIANCE', expiry: expiry)
        expect(result.proceed).to be false
        expect(result.reason).to include('not supported')
      end
    end

    context 'when instrument is not found' do
      before { allow(Instrument).to receive(:find_by).and_return(nil) }

      it 'returns no_trade with instrument not found reason' do
        result = described_class.call(symbol: symbol, expiry: expiry)
        expect(result.proceed).to be false
        expect(result.reason).to include('Instrument not found')
      end
    end

    context 'when insufficient candle data (< 10 candles)' do
      before do
        allow(instrument).to receive(:intraday_ohlc).and_return(
          Array.new(5) { { open: 22000.0, high: 22100.0, low: 21900.0, close: 22000.0, volume: 100 } }
        )
      end

      it 'returns no_trade with insufficient candle reason' do
        result = described_class.call(symbol: symbol, expiry: expiry)
        expect(result.proceed).to be false
        expect(result.reason).to include('Insufficient candle data')
      end
    end

    context 'when LTP is zero (market may be closed)' do
      before { allow(instrument).to receive(:ltp).and_return(0) }

      it 'returns no_trade with LTP unavailable reason' do
        result = described_class.call(symbol: symbol, expiry: expiry)
        expect(result.proceed).to be false
        expect(result.reason).to include('LTP unavailable')
      end
    end

    context 'when no expiry is available' do
      before do
        allow(instrument).to receive(:expiry_list).and_return([])
      end

      it 'returns no_trade with no expiry reason' do
        result = described_class.call(symbol: symbol, expiry: nil)
        expect(result.proceed).to be false
        expect(result.reason).to include('No expiry available')
      end
    end

    context 'when option chain is unavailable' do
      before { allow(instrument).to receive(:fetch_option_chain).and_return(nil) }

      it 'returns no_trade with chain unavailable reason' do
        result = described_class.call(symbol: symbol, expiry: expiry)
        expect(result.proceed).to be false
        expect(result.reason).to include('Option chain unavailable')
      end
    end

    context 'when option chain OC is empty' do
      before { allow(instrument).to receive(:fetch_option_chain).and_return({ last_price: spot, oc: {} }) }

      it 'returns no_trade with OC data empty reason' do
        result = described_class.call(symbol: symbol, expiry: expiry)
        expect(result.proceed).to be false
        expect(result.reason).to include('Option chain OC data empty')
      end
    end

    context 'when regime scorer returns no_trade' do
      let(:regime_result) do
        Trading::RegimeScorer::Result.new(state: :no_trade, trend: nil, reason: 'IV rank too low (15.0): no premium')
      end

      it 'returns no_trade with regime reason' do
        result = described_class.call(symbol: symbol, expiry: expiry)
        expect(result.proceed).to be false
        expect(result.reason).to include('IV rank too low')
      end
    end

    context 'when direction resolver returns nil direction' do
      let(:direction_result) do
        Trading::DirectionResolver::Result.new(
          direction: nil, reason: 'No confirmation: price=bullish oi=bearish',
          vwap: 21900.0, oi_bias: :bearish, price_bias: :bullish
        )
      end

      it 'returns no_trade with no directional signal reason' do
        result = described_class.call(symbol: symbol, expiry: expiry)
        expect(result.proceed).to be false
        expect(result.reason).to include('No directional signal')
      end
    end

    context 'when entry validator returns invalid' do
      let(:entry_result) do
        Trading::EntryValidator::Result.new(valid: false, reason: 'No breakout: close 22000 <= prev high 22050')
      end

      it 'returns no_trade with entry not confirmed reason' do
        result = described_class.call(symbol: symbol, expiry: expiry)
        expect(result.proceed).to be false
        expect(result.reason).to include('Entry not confirmed')
      end
    end

    context 'when chain analysis blocks the trade' do
      let(:chain_analysis) do
        { proceed: false, reason: 'IV rank too high for selling', trend: :bullish, momentum: :flat, adx: 15.0,
          selected: nil, ranked: [] }
      end

      it 'returns no_trade with chain analysis blocked reason' do
        result = described_class.call(symbol: symbol, expiry: expiry)
        expect(result.proceed).to be false
        expect(result.reason).to include('Chain analysis blocked')
      end
    end

    context 'happy path — all gates pass' do
      it 'returns proceed: true with correct fields populated' do
        result = described_class.call(symbol: symbol, expiry: expiry)

        expect(result.proceed).to be true
        expect(result.symbol).to eq('NIFTY')
        expect(result.direction).to eq('CE')
        expect(result.expiry).to eq(expiry)
        expect(result.iv_rank).to eq(40.0)
        expect(result.spot).to eq(spot)
        expect(result.regime).to eq(regime_result)
        expect(result.selected_strike).to be_present
        expect(result.reason).to be_nil
        expect(result.timestamp).to be_present
      end
    end

    context 'SENSEX symbol uses BSE exchange lookup' do
      before do
        allow(Instrument).to receive(:find_by).with(underlying_symbol: 'SENSEX', exchange: 'bse').and_return(instrument)
      end

      it 'looks up by BSE exchange' do
        described_class.call(symbol: 'SENSEX', expiry: expiry)
        expect(Instrument).to have_received(:find_by).with(underlying_symbol: 'SENSEX', exchange: 'bse')
      end
    end
  end
end

