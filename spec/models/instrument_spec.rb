# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Instrument, type: :model do # rubocop:disable RSpecRails/InferredSpecType
  subject { described_class.new(security_id: '12345') }

  describe 'validations' do
    it { is_expected.to validate_presence_of(:security_id) }
  end

  describe 'enums' do
    it do
      expect(subject).to define_enum_for(:exchange)
        .with_values(nse: 'NSE', bse: 'BSE', mcx: 'MCX')
        .backed_by_column_of_type(:string)
    end

    it do
      expect(subject).to define_enum_for(:segment)
        .with_values(
          index: 'I',
          equity: 'E',
          currency: 'C',
          derivatives: 'D',
          commodity: 'M'
        )
        .with_prefix
        .backed_by_column_of_type(:string)
    end
  end

  describe '.lookup_by_symbol' do
    let!(:sensex) do
      create(:instrument,
             security_id: '51', isin: '51', instrument_code: 'index', instrument_type: 'INDEX',
             underlying_symbol: 'SENSEX', symbol_name: 'SENSEX', display_name: 'Sensex',
             series: 'X', exchange: 'bse', segment: 'index')
    end

    it 'finds by underlying_symbol within the exchange/segment scope' do
      expect(described_class.lookup_by_symbol('SENSEX', exchange: :bse, segment: :index)).to eq(sensex)
    end

    it 'upcases and strips the supplied symbol' do
      expect(described_class.lookup_by_symbol(' sensex ', exchange: :bse, segment: :index)).to eq(sensex)
    end

    it 'falls back to symbol_name when underlying_symbol does not match' do
      instrument = create(:instrument, underlying_symbol: nil, symbol_name: 'RELIANCE INDUSTRIES LTD')

      expect(described_class.lookup_by_symbol('RELIANCE INDUSTRIES LTD')).to eq(instrument)
    end

    it 'falls back to a case-insensitive display_name match' do
      nifty = create(:instrument, :nifty, underlying_symbol: nil, symbol_name: 'NIFTY 50 INDEX', display_name: 'Nifty 50')

      expect(described_class.lookup_by_symbol('NIFTY 50', exchange: :nse, segment: :index)).to eq(nifty)
    end

    # Regression: the lookup used to end in find_by(trading_symbol:), a column
    # that does not exist on instruments, so a missing symbol raised
    # PG::UndefinedColumn instead of returning nil.
    it 'returns nil for an unknown symbol' do
      expect(described_class.lookup_by_symbol('NOTASYMBOL', exchange: :bse, segment: :index)).to be_nil
    end

    it 'returns nil for a blank symbol' do
      expect(described_class.lookup_by_symbol(nil)).to be_nil
    end

    it 'does not cross the exchange scope' do
      expect(described_class.lookup_by_symbol('SENSEX', exchange: :nse, segment: :index)).to be_nil
    end
  end
end
