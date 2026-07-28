# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Market::ConfluenceTrader do
  let(:processor) { instance_double(AlertProcessors::Index, call: true) }
  let!(:nifty) { create(:instrument, :nifty) }

  # A Wednesday inside the entry window. MarketCalendar's holiday list is
  # checked too, so the date has to be a real trading day.
  let(:trading_time) { Time.find_zone('Asia/Kolkata').local(2026, 7, 29, 11, 0, 0) }

  def with_env(vars)
    stub_const('ENV', ENV.to_h.merge(vars).compact)
  end

  def enabled_env(overrides = {})
    with_env({
      'INDEX_WATCHLIST' => 'NIFTY,BANKNIFTY,SENSEX',
      'INDEX_WATCHLIST_TRADING' => 'true',
      'INDEX_WATCHLIST_MIN_LEVEL' => 'high'
    }.merge(overrides))
  end

  def signal(symbol: 'NIFTY', bias: :bullish, level: :high, net_score: 9)
    Market::ConfluenceDetector::ConfluenceSignal.new(
      symbol: symbol, bias: bias, net_score: net_score, max_score: 14, level: level,
      factors: [Market::ConfluenceDetector::Factor.new(name: 'MACD', value: 1, note: 'Above signal')],
      close: 24_500.0, atr: 42.5, timestamp: trading_time
    )
  end

  before do
    allow(AlertProcessorFactory).to receive(:build).and_return(processor)
    travel_to(trading_time)
  end

  describe 'the gates' do
    it 'does nothing when INDEX_WATCHLIST_TRADING is off' do
      enabled_env('INDEX_WATCHLIST_TRADING' => 'false')

      expect(described_class.call(signal: signal)).to be_nil
      expect(AlertProcessorFactory).not_to have_received(:build)
      expect(Alert.count).to eq(0)
    end

    it 'ignores a symbol that is not on the watchlist' do
      enabled_env('INDEX_WATCHLIST' => 'BANKNIFTY')

      expect(described_class.call(signal: signal(symbol: 'NIFTY'))).to be_nil
      expect(AlertProcessorFactory).not_to have_received(:build)
    end

    it 'ignores a signal below the configured conviction' do
      enabled_env

      expect(described_class.call(signal: signal(level: :medium, net_score: 6))).to be_nil
      expect(AlertProcessorFactory).not_to have_received(:build)
    end

    it 'trades a medium signal when the floor is lowered' do
      enabled_env('INDEX_WATCHLIST_MIN_LEVEL' => 'medium')

      expect(described_class.call(signal: signal(level: :medium, net_score: 6))).to be_a(Alert)
    end

    # Paper::EodSquareOff closes INTRADAY at 15:15, so a 15:05 entry would be
    # bought and closed within ten minutes.
    it 'refuses an entry after the window closes' do
      enabled_env
      travel_to(trading_time.change(hour: 15, min: 5))

      expect(described_class.call(signal: signal)).to be_nil
      expect(AlertProcessorFactory).not_to have_received(:build)
    end

    it 'refuses an entry before the window opens' do
      enabled_env
      travel_to(trading_time.change(hour: 9, min: 16))

      expect(described_class.call(signal: signal)).to be_nil
    end

    it 'trades exactly on the window boundaries and not a minute outside them' do
      enabled_env('INDEX_WATCHLIST_COOLDOWN_MINUTES' => '1')

      travel_to(trading_time.change(hour: 9, min: 19))
      expect(described_class.call(signal: signal)).to be_nil

      travel_to(trading_time.change(hour: 9, min: 20))
      expect(described_class.call(signal: signal)).to be_a(Alert)

      travel_to(trading_time.change(hour: 15, min: 0))
      expect(described_class.call(signal: signal)).to be_a(Alert)

      travel_to(trading_time.change(hour: 15, min: 1))
      expect(described_class.call(signal: signal)).to be_nil
    end

    it 'never trades outside the session, at any hour of the night' do
      enabled_env

      [0, 3, 8, 16, 20, 23].each do |hour|
        travel_to(trading_time.change(hour: hour, min: 30))
        expect(described_class.call(signal: signal)).to be_nil
      end
      expect(Alert.count).to eq(0)
    end

    it 'refuses to trade at the weekend' do
      enabled_env

      travel_to(Time.find_zone('Asia/Kolkata').local(2026, 8, 1, 11, 0, 0)) # Saturday
      expect(described_class.call(signal: signal)).to be_nil

      travel_to(Time.find_zone('Asia/Kolkata').local(2026, 8, 2, 11, 0, 0)) # Sunday
      expect(described_class.call(signal: signal)).to be_nil

      expect(Alert.count).to eq(0)
    end

    # A weekday the exchange is shut. The session check has to consult the
    # holiday list, not just the day of the week.
    it 'refuses to trade on a weekday market holiday' do
      enabled_env
      travel_to(Time.find_zone('Asia/Kolkata').local(2026, 10, 2, 11, 0, 0)) # Gandhi Jayanti, a Friday

      expect(described_class.call(signal: signal)).to be_nil
      expect(Alert.count).to eq(0)
    end

    # Render runs UTC. If the window were evaluated in the host's zone, the
    # scanner would trade the Indian night and sit idle all session.
    it 'reads the clock in IST even when the host is on UTC' do
      enabled_env

      travel_to(Time.utc(2026, 7, 29, 6, 30)) # 12:00 IST — inside the window
      expect(described_class.call(signal: signal)).to be_a(Alert)

      travel_to(Time.utc(2026, 7, 29, 12, 0)) # 17:30 IST — after the close
      expect(described_class.call(signal: signal)).to be_nil
    end

    it 'skips a symbol the index segment does not carry' do
      enabled_env('INDEX_WATCHLIST' => 'BANKNIFTY')

      expect(described_class.call(signal: signal(symbol: 'BANKNIFTY'))).to be_nil
      expect(Alert.count).to eq(0)
    end
  end

  describe 'cooldown' do
    it 'declines a second signal on the same symbol inside the cooldown' do
      enabled_env('INDEX_WATCHLIST_COOLDOWN_MINUTES' => '30')

      expect(described_class.call(signal: signal)).to be_a(Alert)
      expect(described_class.call(signal: signal)).to be_nil
      expect(Alert.count).to eq(1)
    end

    it 'trades again once the cooldown has expired' do
      enabled_env('INDEX_WATCHLIST_COOLDOWN_MINUTES' => '30')

      described_class.call(signal: signal)
      travel_to(trading_time + 31.minutes)

      expect(described_class.call(signal: signal)).to be_a(Alert)
      expect(Alert.count).to eq(2)
    end

    it 'cools down per symbol, not globally' do
      create(:instrument, :nifty, security_id: '25', underlying_symbol: 'BANKNIFTY', symbol_name: 'BANKNIFTY')
      enabled_env('INDEX_WATCHLIST_COOLDOWN_MINUTES' => '30')

      expect(described_class.call(signal: signal(symbol: 'NIFTY'))).to be_a(Alert)
      expect(described_class.call(signal: signal(symbol: 'BANKNIFTY'))).to be_a(Alert)
    end
  end

  describe 'daily cap' do
    it 'stops after the configured number of entries for the day' do
      enabled_env('INDEX_WATCHLIST_MAX_TRADES_PER_DAY' => '2', 'INDEX_WATCHLIST_COOLDOWN_MINUTES' => '1')

      3.times do |i|
        travel_to(trading_time + (i * 2).minutes)
        described_class.call(signal: signal)
      end

      expect(Alert.count).to eq(2)
    end

    # A skipped alert placed nothing — the processor declined it on its own
    # analysis — so it must not consume the day's budget.
    it 'does not count skipped or failed alerts against the cap' do
      enabled_env('INDEX_WATCHLIST_MAX_TRADES_PER_DAY' => '1', 'INDEX_WATCHLIST_COOLDOWN_MINUTES' => '1')

      described_class.call(signal: signal)
      Alert.last.update!(status: :skipped)
      travel_to(trading_time + 2.minutes)

      expect(described_class.call(signal: signal)).to be_a(Alert)
    end
  end

  describe 'the alert it builds' do
    before { enabled_env }

    it 'maps a bullish signal to a call entry on the normal index pipeline' do
      alert = described_class.call(signal: signal(bias: :bullish))

      expect(alert).to have_attributes(
        ticker: 'NIFTY',
        instrument_type: 'index',
        signal_type: 'long_entry',
        order_type: 'market',
        strategy_type: 'intraday',
        strategy_name: described_class::STRATEGY_NAME,
        instrument_id: nifty.id
      )
      expect(AlertProcessorFactory).to have_received(:build).with(alert)
      expect(processor).to have_received(:call)
    end

    it 'maps a bearish signal to a put entry' do
      alert = described_class.call(signal: signal(bias: :bearish, net_score: -9))

      expect(alert.signal_type).to eq('short_entry')
    end

    it 'records the score that fired it, so the trade can be explained later' do
      alert = described_class.call(signal: signal)

      expect(alert.metadata).to include(
        'triggered_by' => 'index_confluence_scanner',
        'bias' => 'bullish',
        'level' => 'high',
        'net_score' => 9,
        'max_score' => 14
      )
      expect(alert.metadata['factors'].first).to include('name' => 'MACD')
    end

    it 'carries the close the score was computed on as the alert price' do
      alert = described_class.call(signal: signal)

      expect(alert.current_price.to_f).to eq(24_500.0)
    end

    it 'sends SENSEX to BSE' do
      create(:instrument, :nifty, security_id: '51', underlying_symbol: 'SENSEX',
                                  symbol_name: 'SENSEX', exchange: 'bse')

      alert = described_class.call(signal: signal(symbol: 'SENSEX'))

      expect(alert.exchange).to eq('BSE')
    end
  end

  describe 'failure handling' do
    before { enabled_env }

    it 'returns nil instead of raising when the processor blows up' do
      allow(processor).to receive(:call).and_raise(StandardError, 'broker down')

      expect { expect(described_class.call(signal: signal)).to be_nil }.not_to raise_error
    end

    it 'does nothing with a nil signal' do
      expect(described_class.call(signal: nil)).to be_nil
      expect(AlertProcessorFactory).not_to have_received(:build)
    end
  end
end
