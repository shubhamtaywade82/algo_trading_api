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
end
