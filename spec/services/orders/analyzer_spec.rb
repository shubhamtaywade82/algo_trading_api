# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Orders::Analyzer, type: :service do
  include JsonFixtureHelper

  # ─────────────────────────── helpers ─────────────────────────────── #
  def stub_ltp(exchange, id, value)
    allow(MarketCache).to receive(:read_ltp)
      .with(exchange, id)
      .and_return(value)
  end

  # ─────────────────────────── valid paths ─────────────────────────── #
  describe '#call' do
    subject(:analysis) { described_class.call(position) }

    cases = [
      { fixture: 'long_stock',        ltp:  3_400.0,  type: :stock,  long: true  },
      { fixture: 'short_stock',       ltp:  1_450.0,  type: :stock,  long: false },
      { fixture: 'long_call_option',  ltp: 95.0, type: :option, long: true },
      { fixture: 'short_put_option',  ltp: 110.0, type: :option, long: false },
      { fixture: 'currency_option',   ltp: 2.0, type: :option, long: true },
      { fixture: 'index_spot',        ltp: 22_600.0, type: :index, long: true }
    ]

    cases.each do |c|
      context "with #{c[:fixture].tr('_', ' ')}" do
        let(:position) { data_fixture("positions/#{c[:fixture]}") }
        let(:ltp_val)  { c[:ltp] }

        before { stub_ltp(position[:exchangeSegment], position[:securityId], ltp_val) }

        it 'returns correct analysis', :aggregate_failures do
          entry  = position[:costPrice].to_f
          qty    = position[:netQty].abs
          side   = c[:long] ? 1 : -1
          pnl    = ((ltp_val - entry) * qty * side).round(2)
          pct    = (pnl / (entry * qty) * 100).round(2)

          expect(analysis).to include(
            entry_price: entry,
            ltp: ltp_val,
            quantity: qty,
            pnl: pnl,
            pnl_pct: pct,
            instrument_type: c[:type],
            long: c[:long],
            order_type: 'MARKET' # current default in code
          )
        end
      end
    end
  end

  # ─────────────────────── invalid / edge cases ────────────────────── #
  describe '#call with non-analyzable inputs' do
    subject { described_class.call(position) }

    %w[
      invalid_zero_qty
      invalid_zero_cost
      invalid_no_ltp
    ].each do |fix|
      context fix.tr('_', ' ') do
        let(:position) { data_fixture("positions/#{fix}") }

        before { allow(MarketCache).to receive(:read_ltp).and_return(nil) }

        it { is_expected.to eq({}) }
      end
    end
  end
end
