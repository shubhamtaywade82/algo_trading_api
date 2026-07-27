# frozen_string_literal: true

require 'rails_helper'

# db/seeds/index_instruments.csv is the index segment of the detailed scrip
# master, checked in verbatim so that a database which has never run
# `rails instruments:import` can still resolve the symbols the Telegram
# commands and Market::AnalysisService are addressed by.
RSpec.describe 'db/seeds/index_instruments.csv' do
  let(:csv_path) { Rails.root.join('db/seeds/index_instruments.csv') }

  before { InstrumentsImporter.import_from_csv(csv_path.read) }

  it 'lands every row in the index segment' do
    expect(Instrument.count).to eq(Instrument.segment_index.count)
  end

  it 'addresses the indices by DhanHQ IDX_I, which both exchanges share' do
    expect(Instrument.distinct.pluck(:exchange_segment)).to contain_exactly('IDX_I')
  end

  # The three symbols /nifty_analysis, /bank_nifty_analysis and
  # /sensex_analysis resolve, each through the exchange its command passes.
  {
    'NIFTY' => { exchange: :nse, security_id: '13' },
    'BANKNIFTY' => { exchange: :nse, security_id: '25' },
    'SENSEX' => { exchange: :bse, security_id: '51' }
  }.each do |symbol, expected|
    it "resolves #{symbol} to security_id #{expected[:security_id]}" do
      instrument = Instrument.lookup_by_symbol(symbol, exchange: expected[:exchange], segment: :index)

      expect(instrument&.security_id).to eq(expected[:security_id])
    end
  end

  # Market::AnalysisService reads the VIX by security_id, not by symbol.
  it 'carries India VIX at security_id 21' do
    expect(Instrument.find_by(security_id: '21')&.symbol_name).to eq('INDIA VIX')
  end

  it 'is safe to seed twice' do
    expect { InstrumentsImporter.import_from_csv(csv_path.read) }.not_to change(Instrument, :count)
  end

  # A partial feed is not authoritative about what it omits, so seeding the
  # indices must not retire the equities and derivatives a full import loaded.
  it 'retires nothing outside the segment it carries' do
    equity = create(:instrument, last_seen_at: 3.days.ago)

    InstrumentsImporter.import_from_csv(csv_path.read)

    expect(equity.reload).to be_active
  end
end
