# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Instrument do
  it { is_expected.to validate_presence_of(:security_id) }

  it {
    expect(subject).to define_enum_for(:exchange)
      .with_values(nse: 'NSE', bse: 'BSE')
      .backed_by_column_of_type(:string)
  }

  it {
    expect(subject).to define_enum_for(:segment)
      .with_values(index: 'I', equity: 'E', currency: 'C', derivatives: 'D')
      .backed_by_column_of_type(:string)
  }

  describe '#exchange_segment' do
    let(:instrument) { build(:instrument, exchange: 'nse', segment: 'equity') }

    it 'returns the correct exchange segment' do
      expect(instrument.exchange_segment).to eq('NSE_EQ')
    end
  end
end
