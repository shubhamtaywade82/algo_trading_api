# spec/services/alert_processors/stock_spec.rb
# frozen_string_literal: true

require 'rails_helper'
require 'stringio'

RSpec.describe AlertProcessors::Stock, type: :service do
  # ------------------------------------------------------------------
  # ⬇︎ Per-example stubs ------------------------------------------------
  # ------------------------------------------------------------------
  before do
    api_mod  = Module.new
    orders_m = Module.new
    edis_m   = Module.new

    orders_m.module_eval do
      def self.place(*);  end
      def self.modify(*); end
    end

    edis_m.module_eval do
      def self.status(*); end
      def self.mark(*);   end
    end

    api_mod.const_set(:EDIS, edis_m)
    stub_const('Dhanhq::API', api_mod, transfer_nested_constants: true, clone: false)

    allow(Dhanhq::API::Orders).to receive(:place)
      .and_return('orderId' => 'OID', 'orderStatus' => 'PENDING')
    allow(Dhanhq::API::EDIS).to receive(:status)
      .and_return('status' => 'SUCCESS', 'aprvdQty' => 1_000)
    allow(Dhanhq::API::EDIS).to receive(:mark).and_return(true)
  end

  # ------------------------------------------------------------------
  # Shared test doubles & helpers
  # ------------------------------------------------------------------
  let(:instrument) { create(:instrument) }

  def build_alert(overrides = {})
    #
    # 1. create with safe defaults that satisfy model validations
    #
    alert = create(:alert, :pending_status, :delayed,
                   overrides.except(:order_type)
                           .merge(instrument: instrument))

    #
    # 2. if an example wants a *custom* order_type (e.g. "stop_loss_market")
    #    write it directly to the column – bypass validations safely.
    #
    alert.update_column(:order_type, overrides[:order_type]) if overrides.key?(:order_type)

    alert
  end

  # generic processor with defaults; individual examples override attrs
  def processor(alert_overrides = {})
    alert = build_alert(alert_overrides)
    proc  = described_class.new(alert)

    allow(proc).to receive_messages(
      ltp: 100.0,
      available_balance: 100_000.0,
      dhan_positions: [{ 'securityId' => instrument.security_id.to_s, 'netQty' => 0 }],
      logger: Logger.new(StringIO.new, level: :fatal)
    )
    proc
  end

  # ------------------------------------------------------------------
  # SPECS
  # ------------------------------------------------------------------

  describe '#signal_guard?' do
    it 'skips short_entry for long-only strategies' do
      pr = processor(strategy_type: 'long_term', signal_type: 'short_entry')
      expect(pr.signal_guard?).to be_falsey
    end

    it 'allows long_entry while flat' do
      expect(processor.signal_guard?).to be true
    end

    it 'rejects long_exit when flat' do
      pr = processor(signal_type: 'long_exit')
      expect(pr.signal_guard?).to be_falsey
    end
  end

  describe '#build_order_payload' do
    it 'builds LIMIT → SELL payload correctly' do
      pr      = processor(order_type: 'limit', signal_type: 'short_entry')
      payload = pr.build_order_payload

      expect(payload).to include(
        transactionType: 'SELL',
        orderType: 'LIMIT',
        productType: Dhanhq::Constants::INTRA,
        validity: Dhanhq::Constants::DAY,
        exchangeSegment: instrument.exchange_segment,
        securityId: instrument.security_id,
        price: 100.0
      )
    end

    it 'omits price for MARKET orders' do
      expect(processor.build_order_payload).not_to have_key(:price)
    end

    it 'auto-derives a 5 % stop_price when none supplied (SLM order)' do
      pr      = processor(order_type: 'stop_loss_market')
      payload = pr.build_order_payload

      expect(payload[:orderType]).to eq 'STOP_LOSS_MARKET'
      expect(payload).to include(:triggerPrice)

      # short-entry → stop above ltp by ≈5 %
      derived = (pr.ltp * 0.95).round(2)
      expect(payload[:triggerPrice]).to eq(derived)
    end
  end

  describe '#calculate_quantity!' do
    it 'returns capital-aware quantity based on allocation and risk constraints' do
      # With 100K balance and 100 LTP:
      # Allocation: 100K * 0.25 = 25K, 25K / 100 = 250 shares
      # Risk: 100K * 0.035 = 3.5K, 100 * 0.04 = 4 risk/share, 3.5K / 4 = 875 shares
      # Affordability: 100K / 100 = 1000 shares
      # Min of [250, 875, 1000] = 250 shares
      expect(processor.calculate_quantity!).to eq 250
    end

    it 'returns absolute current qty for exit orders' do
      pr = processor(signal_type: 'long_exit')
      allow(pr).to receive(:dhan_positions)
        .and_return([{ 'securityId' => instrument.security_id.to_s, 'netQty' => 50 }])
      expect(pr.calculate_quantity!).to eq 50
    end
  end

  describe '#place_order!' do
    let(:payload) do
      {
        transactionType: 'SELL',
        orderType: 'MARKET',
        productType: Dhanhq::Constants::CNC,
        validity: Dhanhq::Constants::DAY,
        exchangeSegment: instrument.exchange_segment,
        securityId: instrument.security_id,
        quantity: 40
      }
    end

    it 'delegates to Orders.place and guards with eDIS' do
      pr = processor(strategy_type: 'swing', signal_type: 'long_exit')
      allow(pr).to receive(:build_order_payload).and_return(payload)
      allow(pr).to receive(:ensure_edis!)

      expect(Dhanhq::API::Orders).to receive(:place).with(payload)
      expect(pr).to receive(:ensure_edis!).with(40)
      pr.place_order!(payload)
    end
  end
end
