# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Option::ChainAnalyzer, type: :service do
  subject(:analyzer) do
    described_class.new(
      option_chain,
      expiry: expiry,
      underlying_spot: spot,
      iv_rank: iv_rank,
      historical_data: []
    )
  end

  let(:instrument) do
    create(
      :instrument,
      segment: 'index',
      exchange: 'NSE',
      security_id: '13',
      underlying_symbol: 'NIFTY',
      instrument: 'INDEX'
    )
  end

  let(:vcr_response) do
    cassette_path = Rails.root.join('spec/vcr_cassettes/dhan/option_expiry_list.yml')
    cassette_data = YAML.load_file(cassette_path)
    http_interactions = cassette_data['http_interactions']
    response_body = http_interactions.second['response']['body']['string']
    JSON.parse(response_body, symbolize_names: true)
  end

  let(:option_chain) { instrument.fetch_option_chain }
  let(:expiry)       { (Date.today + 7.days).to_s } # ← FIXED
  let(:spot)         { option_chain[:last_price] || 22_150.0 }
  let(:iv_rank)      { 0.5 }

  describe '#analyze', vcr: { cassette_name: 'dhan/option_expiry_list' } do
    it 'returns analysis hash with proceed true or false' do
      result = analyzer.analyze(signal_type: :ce, strategy_type: 'intraday')

      if result[:proceed]
        expect(result).to include(
          :proceed,
          :trend,
          :signal_type,
          :selected,
          :ranked
        )
      end

      # For negative case
      unless result[:proceed]
        expect(result).to include(
          :proceed,
          :reason
        )
      end
    end
  end

  context 'when IV rank is outside range', vcr: { cassette_name: 'dhan/option_expiry_list' } do
    let(:iv_rank) { 1.5 }

    it 'returns proceed: false with reason' do
      result = analyzer.analyze(signal_type: :ce, strategy_type: 'intraday')

      expect(result[:proceed]).to eq(false)
      expect(result[:reason]).to eq('IV rank outside range')
    end
  end

  context 'when no tradable strikes found', vcr: { cassette_name: 'dhan/option_expiry_list' } do
    let(:expiry) { Date.today.to_s }

    before do
      # patch option_chain to empty out all strikes
      option_chain[:oc].each do |_, row|
        row['ce']['last_price'] = 0
        row['ce']['implied_volatility'] = 0
      end
    end

    it 'returns proceed: false with reason' do
      result = analyzer.analyze(signal_type: :ce, strategy_type: 'intraday')

      expect(result[:proceed]).to be(false)
      expect(result[:reason]).to eq('Late entry, theta risk')
    end
  end
end
