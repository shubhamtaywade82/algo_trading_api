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

    it 'at-a-glance shows ATM and OTM strikes with LTP, IV, Δ, θ' do
      formatted = service.send(:format_options_at_a_glance, options)

      expect(formatted).to include('ATM 12345')
      expect(formatted).to include('CE ₹12.35')
      expect(formatted).to include('PE ₹–')
      expect(formatted).not_to include('Γ')
      expect(formatted).not_to include('OI')
    end

    it 'at-a-glance includes OTM+1 and OTM−1 when present in options' do
      options_with_otm = options.merge(
        otm_call: { strike: 12_350, call: { 'last_price' => 10 }, put: { 'last_price' => 15 } },
        otm_put: { strike: 12_340, call: { 'last_price' => 15 }, put: { 'last_price' => 10 } }
      )
      formatted = service.send(:format_options_at_a_glance, options_with_otm)

      expect(formatted).to include('ATM 12345')
      expect(formatted).to include('OTM+1 (CALL) 12350')
      expect(formatted).to include('OTM−1 (PUT) 12340')
    end
  end
end
