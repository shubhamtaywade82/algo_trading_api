# frozen_string_literal: true

require 'rails_helper'
require 'stringio'

# A CNC position is in the *position* book only on its trade date; from T+1 the
# broker reports it as a holding. Exit logic that only ever looked at positions
# saw zero and skipped, so a swing or long-term position was never closed on any
# day but the first.
RSpec.describe AlertProcessors::Stock, type: :service do
  let(:instrument) { create(:instrument, security_id: '1333') }
  let(:flat_position) { [{ 'securityId' => '1333', 'netQty' => 0 }] }
  let(:holding) { [{ 'securityId' => '1333', 'totalQty' => 40, 'availableQty' => 40 }] }

  def processor_for(strategy_type:, signal_type:, positions:, holdings:)
    alert = create(:alert, :pending_status, :delayed,
                   instrument: instrument, strategy_type: strategy_type, signal_type: signal_type)
    described_class.new(alert).tap do |proc|
      allow(proc).to receive_messages(
        ltp: 100.0, available_balance: 100_000.0,
        dhan_positions: positions, dhan_holdings: holdings,
        logger: Logger.new(StringIO.new, level: :fatal)
      )
    end
  end

  it 'finds a swing position that has moved to holdings' do
    proc = processor_for(strategy_type: 'swing', signal_type: 'long_exit',
                         positions: flat_position, holdings: holding)

    expect(proc.current_qty).to eq(40)
  end

  it 'lets the exit through instead of skipping as :no_long' do
    proc = processor_for(strategy_type: 'swing', signal_type: 'long_exit',
                         positions: flat_position, holdings: holding)

    expect(proc.signal_guard?).to be(true)
  end

  it 'sells only the free quantity, never the part pending delivery' do
    proc = processor_for(strategy_type: 'long_term', signal_type: 'long_exit',
                         positions: flat_position,
                         holdings: [{ 'securityId' => '1333', 'totalQty' => 40, 'availableQty' => 25 }])

    expect(proc.current_qty).to eq(25)
  end

  # Intraday is squared off daily and never becomes a holding, so a holdings
  # fallback there would be reading someone else's position.
  it 'does not consult holdings for an intraday signal' do
    proc = processor_for(strategy_type: 'intraday', signal_type: 'long_exit',
                         positions: flat_position, holdings: holding)

    expect(proc.current_qty).to eq(0)
  end

  it 'prefers the position book while the position is still in it' do
    proc = processor_for(strategy_type: 'swing', signal_type: 'long_exit',
                         positions: [{ 'securityId' => '1333', 'netQty' => 15 }], holdings: holding)

    expect(proc.current_qty).to eq(15)
  end

  # eDIS authorises a depository debit of real shares. Running it for a
  # simulated sell calls the live API and blocks the placement for up to 45s.
  describe 'eDIS' do
    around do |example|
      original = ENV.fetch('PAPER_TRADING', nil)
      ENV['PAPER_TRADING'] = 'true'
      example.run
      ENV['PAPER_TRADING'] = original
    end

    it 'is skipped in paper mode' do
      allow(Dhanhq::API::EDIS).to receive(:status)
      proc = processor_for(strategy_type: 'swing', signal_type: 'long_exit',
                           positions: flat_position, holdings: holding)

      proc.send(:ensure_edis!, 40)

      expect(Dhanhq::API::EDIS).not_to have_received(:status)
    end
  end
end
