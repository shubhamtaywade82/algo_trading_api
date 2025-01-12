# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Option::ChainAnalyzer, type: :service do
  let(:option_chain) do
    {
      oc: {
        15_000 => { ce: { last_price: 100, oi: 2000 }, pe: { last_price: 90, oi: 1000 } },
        15_100 => { ce: { last_price: 120, oi: 1500 }, pe: { last_price: 80, oi: 800 } }
      }
    }
  end
  let(:analyzer) { described_class.new(option_chain) }

  describe '#analyze' do
    it 'returns a valid analysis hash' do
      analysis = analyzer.analyze

      expect(analysis).to have_key(:max_pain)
      expect(analysis).to have_key(:support_resistance)
    end
  end
end
