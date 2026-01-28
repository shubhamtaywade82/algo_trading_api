# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Option chain formatting' do
  let(:options) do
    {
      atm: {
        strike: 12_345,
        call: { 'last_price' => 12.345 }
        # put missing to simulate incomplete row
      }
    }
  end

  describe Market::AnalysisService do
    subject(:service) { described_class.new('NIFTY') }

    it 'handles incomplete rows with placeholders' do
      formatted = service.send(:format_options_chain, options)

      expect(formatted).to include('CALL: LTP ₹12.35')
      expect(formatted).to include('IV –%')
      expect(formatted).to include('PUT : LTP ₹–')
    end
  end
end
