# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::MarketFeedHub do
  subject(:hub) { described_class.instance }

  let(:callbacks) { {} }
  let(:ws_client) do
    double('WSClient').tap do |client|
      allow(client).to receive(:on) { |event, &blk|
        callbacks[event] = blk
        client
      }
      allow(client).to receive(:stop)
      allow(client).to receive(:subscribe_one)
      allow(client).to receive(:unsubscribe_one)
      allow(client).to receive_messages(start: client, connected?: true, healthy?: true, health: { connected: true })
    end
  end

  before do
    # Singleton: reset the memoised state between examples.
    described_class.instance_variable_set(:@singleton__instance__, nil)
    Live::TickCache.clear!
    allow(DhanHQ::WS::Client).to receive(:new).and_return(ws_client)
  end

  after do
    described_class.instance_variable_set(:@singleton__instance__, nil)
    Live::TickCache.clear!
  end

  describe 'lifecycle' do
    it 'is not running before start' do
      expect(hub).not_to be_running
      expect(hub).not_to be_connected
    end

    it 'starts once and is idempotent' do
      hub.start!
      hub.start!

      expect(DhanHQ::WS::Client).to have_received(:new).once
      expect(hub).to be_running
    end

    it 'survives a failure to open the socket' do
      allow(ws_client).to receive(:start).and_raise(StandardError, 'no network')

      hub.start!

      expect(hub).not_to be_running
    end

    it 'stops cleanly' do
      hub.start!
      hub.stop!

      expect(hub).not_to be_running
      expect(ws_client).to have_received(:stop)
    end
  end

  describe 'connected?' do
    # A feed can stay connected while the server stops publishing, so health
    # is judged on frame arrival, not socket state.
    it 'is false when the socket is up but frames have gone stale' do
      allow(ws_client).to receive(:healthy?).and_return(false)
      hub.start!

      expect(hub).not_to be_connected
    end

    it 'is true when the socket is up and frames are arriving' do
      hub.start!

      expect(hub).to be_connected
    end
  end

  describe 'subscriptions' do
    it 'subscribes and tracks the instrument' do
      hub.start!

      expect(hub.subscribe(segment: 'NSE_FNO', security_id: 49_081)).to be(true)
      expect(ws_client).to have_received(:subscribe_one).with(segment: 'NSE_FNO', security_id: '49081')
      expect(hub.subscriptions.size).to eq(1)
    end

    it 'does not resubscribe a duplicate' do
      hub.start!
      hub.subscribe(segment: 'NSE_FNO', security_id: '49081')
      hub.subscribe(segment: 'NSE_FNO', security_id: '49081')

      expect(ws_client).to have_received(:subscribe_one).once
    end

    it 'unsubscribes and drops the cached tick' do
      hub.start!
      hub.subscribe(segment: 'NSE_FNO', security_id: '49081')
      Live::TickCache.put('NSE_FNO', '49081', ltp: 10.0)

      hub.unsubscribe(segment: 'NSE_FNO', security_id: '49081')

      expect(hub.subscriptions).to be_empty
      expect(Live::TickCache.ltp('NSE_FNO', '49081')).to be_nil
    end

    it 'refuses to exceed the per-connection cap' do
      hub.start!
      stub_const("#{described_class}::MAX_SUBSCRIPTIONS", 1)
      hub.subscribe(segment: 'NSE_FNO', security_id: '1')

      expect(hub.subscribe(segment: 'NSE_FNO', security_id: '2')).to be(false)
    end

    # Instruments subscribed while the socket was down were never seen by the
    # SDK, so the hub replays its own set on start.
    it 'replays tracked subscriptions on start' do
      hub.subscribe(segment: 'NSE_FNO', security_id: '49081')
      hub.start!

      expect(ws_client).to have_received(:subscribe_one).with(segment: 'NSE_FNO', security_id: '49081')
    end
  end

  describe 'tick handling' do
    it 'writes decoded ticks into the cache' do
      hub.start!

      callbacks[:tick].call(kind: :quote, segment: 'NSE_FNO', security_id: '49081', ltp: 250.5)

      expect(Live::TickCache.ltp('NSE_FNO', '49081')).to eq(250.5)
    end

    it 'ignores a tick with no instrument' do
      hub.start!

      expect { callbacks[:tick].call(kind: :quote, ltp: 1.0) }.not_to raise_error
      expect(Live::TickCache.size).to eq(0)
    end
  end

  describe 'reconnect' do
    # Prices from before the gap must not be traded on.
    it 'clears the tick cache and replays subscriptions' do
      hub.start!
      hub.subscribe(segment: 'NSE_FNO', security_id: '49081')
      Live::TickCache.put('NSE_FNO', '49081', ltp: 999.0)

      callbacks[:reconnect].call(attempt: 1, resubscribed: ['NSE_FNO:49081'])

      expect(Live::TickCache.ltp('NSE_FNO', '49081')).to be_nil
      expect(ws_client).to have_received(:subscribe_one).at_least(:twice)
    end
  end

  describe '#health' do
    it 'reports feed and cache state' do
      hub.start!
      hub.subscribe(segment: 'NSE_FNO', security_id: '49081')

      expect(hub.health).to include(running: true, tracked_subscriptions: 1)
    end
  end
end
