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

  describe 'numeric validations' do
    it { is_expected.to validate_numericality_of(:lot_size).is_greater_than(0).allow_nil }
    it { is_expected.to validate_numericality_of(:tick_size).is_greater_than_or_equal_to(0).allow_nil }
    it { is_expected.to validate_numericality_of(:strike_price).is_greater_than_or_equal_to(0).allow_nil }
  end

  # The importer writes through activerecord-import, which skips validations, so
  # these constraints — not the model — are what actually stands between a
  # malformed scrip-master row and a live order sized off it.
  #
  # update_column throughout: bypassing the model is the point — these examples
  # assert what the database rejects on its own.
  # rubocop:disable Rails/SkipsModelValidations
  describe 'CHECK constraints' do
    let(:instrument) { create(:instrument) }

    it 'rejects a non-positive lot_size' do
      expect { instrument.update_column(:lot_size, 0) }
        .to raise_error(ActiveRecord::StatementInvalid, /chk_instruments_lot_size_positive/)
    end

    it 'rejects a negative tick_size' do
      expect { instrument.update_column(:tick_size, -0.05) }
        .to raise_error(ActiveRecord::StatementInvalid, /chk_instruments_tick_size_non_negative/)
    end

    it 'rejects a negative strike_price' do
      expect { instrument.update_column(:strike_price, -100) }
        .to raise_error(ActiveRecord::StatementInvalid, /chk_instruments_strike_price_non_negative/)
    end

    it 'rejects an option_type outside CE/PE' do
      expect { instrument.update_column(:option_type, 'XX') }
        .to raise_error(ActiveRecord::StatementInvalid, /chk_instruments_option_type_valid/)
    end

    it 'allows the NULLs the feed legitimately produces' do
      expect { instrument.update_columns(lot_size: nil, tick_size: nil, strike_price: nil, option_type: nil) }
        .not_to raise_error
    end
  end
  # rubocop:enable Rails/SkipsModelValidations

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
