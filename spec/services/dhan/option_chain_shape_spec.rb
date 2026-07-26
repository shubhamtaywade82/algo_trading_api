# frozen_string_literal: true

require 'rails_helper'

# DhanHQ >= 3.0 returns the option chain as
#   { last_price:, strikes: [{ strike:, call:, put: }] }
# where <= 2.x returned
#   { last_price:, oc: { "23000.000000" => { "ce" => {}, "pe" => {} } } }
#
# Dhan::MarketDataService adapts the new shape back to `oc`, which every
# Option::* analyzer indexes into.
RSpec.describe Dhan::MarketDataService do
  subject(:service) { described_class.new(instrument) }

  # A plain double, not instance_double(Instrument): app/models/instrument.rb
  # currently has a syntax error from an unresolved merge, so referencing the
  # class here would fail to load for reasons unrelated to this behaviour.
  let(:instrument) do
    double('Instrument', security_id: '13', exchange_segment: 'IDX_I')
  end

  let(:call_leg) { { 'last_price' => 120.5, 'oi' => 500, 'implied_volatility' => 14.2 } }
  let(:put_leg)  { { 'last_price' => 80.25, 'oi' => 700, 'implied_volatility' => 15.1 } }

  let(:v3_response) do
    {
      last_price: 23_050.0,
      strikes: [
        { strike: 23_000.0, call: call_leg, put: put_leg }
      ]
    }.with_indifferent_access
  end

  before do
    allow(DhanHQ::Models::OptionChain).to receive(:fetch_expiry_list).and_return(['2026-08-06'])
  end

  it 'adapts the 3.x strikes array into the strike-keyed oc hash' do
    allow(DhanHQ::Models::OptionChain).to receive(:fetch).and_return(v3_response)

    chain = service.fetch_option_chain('2026-08-06')

    expect(chain[:last_price]).to eq(23_050.0)
    expect(chain[:oc].keys).to eq(['23000.000000'])
  end

  it 'keys strikes with the %.6f format the chain analyzers look up by' do
    allow(DhanHQ::Models::OptionChain).to receive(:fetch).and_return(v3_response)

    chain = service.fetch_option_chain('2026-08-06')

    # Option::ChainAnalyzer scoring does oc[format('%.6f', strike)]
    expect(chain[:oc][format('%.6f', 23_000.0)]).to be_present
  end

  it 'maps call/put back onto the ce/pe leg names' do
    allow(DhanHQ::Models::OptionChain).to receive(:fetch).and_return(v3_response)

    legs = service.fetch_option_chain('2026-08-06')[:oc]['23000.000000']

    expect(legs['ce']['last_price']).to eq(120.5)
    expect(legs['pe']['last_price']).to eq(80.25)
  end

  it 'still accepts the legacy oc-shaped response' do
    legacy = {
      last_price: 23_050.0,
      oc: { '23000.000000' => { 'ce' => call_leg, 'pe' => put_leg } }
    }.with_indifferent_access
    allow(DhanHQ::Models::OptionChain).to receive(:fetch).and_return(legacy)

    chain = service.fetch_option_chain('2026-08-06')

    expect(chain[:oc]['23000.000000']['ce']['last_price']).to eq(120.5)
  end

  it 'drops strikes whose legs carry no tradable values' do
    empty_leg = { 'last_price' => 0, 'oi' => 0, 'implied_volatility' => 12.0 }
    response = {
      last_price: 23_050.0,
      strikes: [
        { strike: 23_000.0, call: call_leg, put: put_leg },
        { strike: 23_100.0, call: empty_leg, put: empty_leg }
      ]
    }.with_indifferent_access
    allow(DhanHQ::Models::OptionChain).to receive(:fetch).and_return(response)

    chain = service.fetch_option_chain('2026-08-06')

    expect(chain[:oc].keys).to eq(['23000.000000'])
  end
end
