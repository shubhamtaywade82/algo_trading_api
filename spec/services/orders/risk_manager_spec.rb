# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Orders::RiskManager, type: :service do
  # ------------------------------------------------------------------
  # Helpers already available in your spec_helper / support files:
  #   • build(:option_position)
  #   • stub_charges(0)
  #   • stub_chain_trend(value)   – :bullish / :bearish / nil
  #   • stub_spot_ltp(value)
  # ------------------------------------------------------------------
  let(:position) { build(:option_position) }

  def analysis(attrs = {})
    {
      entry_price: 100,
      ltp: 100,
      quantity: 75,
      pnl: 0,
      pnl_pct: 0,
      instrument_type: :option
    }.merge(attrs)
  end

  before do
    Rails.cache.clear
    stub_charges(0)
    stub_chain_trend(nil)
  end

  # ------------------------------------------------------------
  # ① Emergency-loss Exit
  # ------------------------------------------------------------
  it 'exits on emergency rupee loss' do
    result = described_class.call(position, analysis(pnl: -6_000, pnl_pct: -60))
    expect(result).to include(exit_reason: 'EmergencyStopLoss')
  end

  # ------------------------------------------------------------
  # ② Take-Profit Exit
  # ------------------------------------------------------------
  it 'exits on take-profit target' do
    result = described_class.call(position, analysis(pnl: 2_600, pnl_pct: 35))
    expect(result).to include(exit_reason: 'TakeProfit')
  end

  # ------------------------------------------------------------
  # ③ Danger-Zone Exit (after 5 bars OR deep loss)
  # ------------------------------------------------------------
  it 'exits after 5 consecutive danger-zone bars' do
    4.times { described_class.call(position, analysis(pnl: -1_000, pnl_pct: -10)) }
    result = described_class.call(position, analysis(pnl: -1_000, pnl_pct: -10))
    expect(result).to include(exit_reason: 'DangerZone')
  end

  # ------------------------------------------------------------
  # ④ Trend-Reversal Exit (3 bars against bias)
  # ------------------------------------------------------------
  it 'exits on confirmed trend reversal (3 bearish vs long CE)' do
    stub_chain_trend(:bearish)
    2.times { described_class.call(position, analysis(pnl_pct: 2)) } # warm-up
    result = described_class.call(position, analysis(pnl_pct: 2))
    expect(result).to include(exit_reason: 'TrendReversalExit')
  end

  # ------------------------------------------------------------
  # ⑤ Spot Trend-Break Exit
  # ------------------------------------------------------------
  it 'exits when spot price breaks entry trend' do
    custom = analysis(spot_entry_price: 22_500, pnl_pct: 5)
    stub_spot_ltp(22_000) # spot below entry ⇒ break for long CE
    result = described_class.call(position, custom)
    expect(result).to include(exit_reason: 'TrendBreakExit')
  end

  # ------------------------------------------------------------
  # ⑥ Percentage Stop-Loss Exit
  # ------------------------------------------------------------
  it 'exits on hard % stop-loss' do
    result = described_class.call(position, analysis(pnl: -1_200, pnl_pct: -20))
    expect(result).to include(exit_reason: 'StopLoss')
  end

  # ------------------------------------------------------------
  # ⑦ Break-Even Exit
  # ------------------------------------------------------------
  it 'exits at break-even after large prior gains' do
    # ➊ record a peak gain
    described_class.call(position, analysis(pnl_pct: 15))
    # ➋ now price drifts back to entry
    res = described_class.call(position, analysis(pnl_pct: 0.1, ltp: 100.1))
    expect(res).to include(exit_reason: 'BreakEvenTrail')
  end

  # ------------------------------------------------------------
  # ⑧ Trailing-Stop Adjustment
  # ------------------------------------------------------------
  it 'returns adjust hash when draw-down exceeds buffer' do
    described_class.call(position, analysis(pnl_pct: 25)) # create max_pct
    result = described_class.call(position, analysis(pnl_pct: 18, ltp: 118))

    expect(result).to include(exit: false, adjust: true)
    expect(result[:adjust_params]).to have_key(:trigger_price)
  end

  # ------------------------------------------------------------
  # ⑨ No-Action Path
  # ------------------------------------------------------------
  it 'does nothing when no rule triggers' do
    res = described_class.call(position, analysis(pnl_pct: 5))
    expect(res).to eq(exit: false, adjust: false)
  end
end
