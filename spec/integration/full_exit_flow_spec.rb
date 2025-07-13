# spec/integration/full_exit_flow_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Full Exit Flow', type: :integration do
  include TestStubs # helpers: stub_charges, stub_chain_trend, stub_spot_ltp
  let(:position) { build(:option_position) }

  # All specs need these stubs
  before do
    Rails.cache.clear
    stub_charges(0)
    allow(TelegramNotifier).to     receive(:send_message)
    allow(Dhanhq::API::Orders).to  receive(:place).and_return('orderStatus' => 'PENDING', 'orderId' => 'OID')
    allow(Dhanhq::API::Orders).to  receive(:modify).and_return({ 'status' => 'success' })
    allow(Dhanhq::API::Orders).to  receive(:list).and_return([])
    allow(Rails.logger).to         receive_messages(info: nil, warn: nil, error: nil)

    # Unless a spec overrides it we don’t want ChainAnalyzer or MarketCache doing work
    stub_chain_trend(nil)
    stub_spot_ltp(nil)
  end

  def drive_stack(position_hash, analysis_hash)
    # Use real RiskManager via Manager – this is the “full” path
    allow(Orders::Analyzer).to receive(:call).with(position_hash).and_return(analysis_hash)
    if Positions::Manager
      Orders::Manager.call(position_hash, analysis_hash)
    else
      Orders::Manager.call(position_hash, analysis_hash)
    end
  end

  # --------------------------------------------------------------------------------------------------------------------
  context 'emergency-loss path' do
    let(:analysis) { { entry_price: 100, ltp: 20, quantity: 75, pnl: -6_000, pnl_pct: -60, instrument_type: :option } }

    it 'routes to EmergencyStopLoss' do
      expect(Orders::Executor).to receive(:call)
        .with(position.with_indifferent_access, 'EmergencyStopLoss', hash_including(pnl: -6_000))

      drive_stack(position, analysis)
    end
  end

  # --------------------------------------------------------------------------------------------------------------------
  context 'take-profit path' do
    let(:analysis) { { entry_price: 100, ltp: 140, quantity: 75, pnl: 3_000, pnl_pct: 40, instrument_type: :option } }

    it 'routes to TakeProfit' do
      expect(Orders::Executor).to receive(:call)
        .with(position.with_indifferent_access, 'TakeProfit', hash_including(pnl: 3_000))

      drive_stack(position, analysis)
    end
  end

  # --------------------------------------------------------------------------------------------------------------------
  context 'danger-zone after 5 bars' do
    # within -2k … -1k
    let(:dz_analysis) do
      { entry_price: 100, ltp: 85, quantity: 75, pnl: -1_125, pnl_pct: -15, instrument_type: :option }
    end

    it 'routes to DangerZone on 5th bar' do
      4.times { drive_stack(position, dz_analysis) }     # warm-up cache
      expect(Orders::Executor).to receive(:call)
        .with(position.with_indifferent_access, 'DangerZone', hash_including(pnl: -1_125))

      drive_stack(position, dz_analysis)                 # 5th call
    end
  end

  # --------------------------------------------------------------------------------------------------------------------
  context 'trend-reversal (3 bars vs bias)' do
    let(:analysis) { { entry_price: 100, ltp: 102, quantity: 75, pnl: 150, pnl_pct: 2, instrument_type: :option } }

    before do
      stub_chain_trend(:bearish) # long CE vs bearish chain
      stub_spot_ltp(22_600) # any non-nil spot will do
      allow_any_instance_of(Orders::RiskManager).to receive(:trend_for_position).and_return(:bearish)
    
    end

    it 'routes to TrendReversalExit on 3rd bar' do
      3.times { drive_stack(position, analysis) }        # first two bars
      expect(Orders::Executor).to receive(:call)
        .with(position.with_indifferent_access, 'TrendReversalExit', hash_including(pnl_pct: 2))

      drive_stack(position, analysis)                    # third bar
    end
  end

  # --------------------------------------------------------------------------------------------------------------------
  context 'spot trend-break' do
    let(:analysis) do
      { entry_price: 100, ltp: 106, quantity: 75, pnl: 450, pnl_pct: 6, instrument_type: :option,
        spot_entry_price: 22_500 }
    end

    before { stub_spot_ltp(22_000) } # breaks lower

    it 'routes to TrendBreakExit' do
      expect(Orders::Executor).to receive(:call).with(position.with_indifferent_access, 'TrendBreakExit', anything)
      drive_stack(position, analysis)
    end
  end

  # --------------------------------------------------------------------------------------------------------------------
  context 'hard %-stop-loss' do
    let(:analysis) do
      { entry_price: 100, ltp: 84, quantity: 75,
        pnl: -1_200, pnl_pct: -16, instrument_type: :option }
    end

    it 'routes to StopLoss' do
      expect(Orders::Executor).to receive(:call)
        .with(position.with_indifferent_access, 'StopLoss', anything)

      drive_stack(position, analysis)
    end
  end

  # --------------------------------------------------------------------------------------------------------------------
  context 'break-even exit' do
    let(:peak_analysis)   { { entry_price: 100, ltp: 115, quantity: 75, pnl: 1_125, pnl_pct: 15, instrument_type: :option } }
    let(:flat_analysis)   { { entry_price: 100, ltp: 100.3, quantity: 75, pnl: 22.5, pnl_pct: 0.3, instrument_type: :option } }

    it 'fires BreakEvenTrail after gains revert' do
      drive_stack(position, peak_analysis) # record max_pct
      expect(Orders::Executor).to receive(:call).with(position.with_indifferent_access, 'BreakEvenTrail', anything)
      drive_stack(position, flat_analysis)
    end
  end

  # --------------------------------------------------------------------------------------------------------------------
  context 'trailing-SL adjust (no exit)' do
    # peak must stay < 30 % so TP rule is NOT triggered, but ≥ 15 % to activate tight trail
    let(:peak)   { { entry_price: 100, ltp: 125, quantity: 75, pnl: 1_875, pnl_pct: 25, instrument_type: :option } }
    let(:pullbk) { { entry_price: 100, ltp: 118, quantity: 75, pnl: 1_350, pnl_pct: 18, instrument_type: :option } }

    it 'calls Orders::Adjuster with trigger_price only' do
      drive_stack(position, peak) # establish max_pct = 25
      expect(Orders::Adjuster).to receive(:call)
        .with(position.with_indifferent_access, hash_including(:trigger_price))

      drive_stack(position, pullbk)
    end
  end

  # --------------------------------------------------------------------------------------------------------------------
  context 'no rule triggers' do
    let(:analysis) { { entry_price: 100, ltp: 105, quantity: 75, pnl: 375, pnl_pct: 5, instrument_type: :option } }

    it 'does not call Executor or Adjuster' do
      expect(Orders::Executor).not_to receive(:call)
      expect(Orders::Adjuster).not_to receive(:call)
      drive_stack(position, analysis)
    end
  end
end
