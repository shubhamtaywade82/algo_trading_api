# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Crypto::Binance::KlineStream do
  subject(:stream) { described_class.new(symbols: %w[SOLUSDT ETHUSDT], timeframes: %w[5m 15m], on_close: handler) }

  let(:fired) { [] }
  let(:handler) { ->(symbol, timeframe) { fired << [symbol, timeframe] } }

  # Shaped like a real combined-stream frame: Binance carries the symbol at
  # the event level *and* inside the kline.
  def frame(symbol: 'SOLUSDT', interval: '5m', closed: true)
    { stream: "#{symbol.downcase}@kline_#{interval}",
      data: { e: 'kline', E: 1_767_000_000_000, s: symbol,
              k: { t: 1_767_000_000_000, s: symbol, i: interval, x: closed,
                   o: '151.00', h: '153.00', l: '150.50', c: '152.30', v: '1200' } } }.to_json
  end

  # A raw single stream is not wrapped in "data".
  def raw_frame(symbol: 'SOLUSDT', interval: '5m')
    { e: 'kline', s: symbol, k: { s: symbol, i: interval, x: true, c: '152.30' } }.to_json
  end

  describe '#stream_url' do
    it 'subscribes to every symbol on every timeframe over one socket' do
      expect(stream.stream_url).to eq(
        'wss://fstream.binance.com/stream?streams=' \
        'solusdt@kline_5m/solusdt@kline_15m/ethusdt@kline_5m/ethusdt@kline_15m'
      )
    end

    it 'defaults to the configured symbols and stream timeframes' do
      allow(Crypto::Config).to receive_messages(symbols: %w[SOLUSDT], stream_timeframes: %w[5m])

      expect(described_class.new.stream_url).to end_with('streams=solusdt@kline_5m')
    end
  end

  describe 'handling frames' do
    it 'scans when a candle closes' do
      stream.send(:handle_message, frame)

      expect(fired).to eq([%w[SOLUSDT 5m]])
    end

    it 'reads a raw single-stream frame too' do
      stream.send(:handle_message, raw_frame)

      expect(fired).to eq([%w[SOLUSDT 5m]])
    end

    it 'ignores a candle that is still forming' do
      stream.send(:handle_message, frame(closed: false))

      expect(fired).to be_empty
    end

    it 'collapses two timeframes closing on the same boundary into one scan' do
      stream.send(:handle_message, frame(interval: '5m'))
      stream.send(:handle_message, frame(interval: '15m'))

      expect(fired.size).to eq(1)
    end

    it 'still scans the other symbol on that boundary' do
      stream.send(:handle_message, frame(symbol: 'SOLUSDT'))
      stream.send(:handle_message, frame(symbol: 'ETHUSDT'))

      expect(fired.map(&:first)).to eq(%w[SOLUSDT ETHUSDT])
    end

    it 'scans again once the debounce window has passed' do
      stream.send(:handle_message, frame)

      travel_to((described_class::DEBOUNCE_SECONDS + 1).seconds.from_now) do
        stream.send(:handle_message, frame)
      end

      expect(fired.size).to eq(2)
    end

    it 'survives an unparseable frame' do
      expect { stream.send(:handle_message, 'not json') }.not_to raise_error
      expect(fired).to be_empty
    end

    it 'ignores a frame that carries no kline' do
      expect { stream.send(:handle_message, '{"result":null,"id":1}') }.not_to raise_error
      expect(fired).to be_empty
    end

    it 'does not let a failing handler kill the socket' do
      boom = described_class.new(symbols: %w[SOLUSDT], on_close: ->(_s, _t) { raise 'handler exploded' })

      expect { boom.send(:handle_message, frame) }.not_to raise_error
    end
  end

  describe 'the safety-net scan' do
    it 'skips a symbol the stream already covered' do
      stream.send(:handle_message, frame(symbol: 'SOLUSDT'))

      expect(stream.send(:recently_scanned?, 'SOLUSDT')).to be(true)
      expect(stream.send(:recently_scanned?, 'ETHUSDT')).to be(false)
    end

    it 'covers a symbol again once the interval lapses' do
      stream.send(:handle_message, frame(symbol: 'SOLUSDT'))

      travel_to((described_class::SAFETY_SCAN_INTERVAL + 1).seconds.from_now) do
        expect(stream.send(:recently_scanned?, 'SOLUSDT')).to be(false)
      end
    end
  end
end
