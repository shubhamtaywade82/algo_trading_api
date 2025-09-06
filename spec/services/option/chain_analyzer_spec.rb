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
    let(:stub_time) { Time.zone.local(2025, 1, 1, 15, 30) }
    let(:expiry) { stub_time.to_date.to_s }

    before do
      option_chain[:oc].each_value do |row|
        %w[ce pe].each do |side|
          next unless row[side]

          row[side]['last_price']         = 0
          row[side]['implied_volatility'] = 0
        end
      end

      # ⬇︎ freeze time so theta-guard triggers (avoids receive_message_chain)
      travel_to(stub_time)
    end

    it 'returns proceed: false with late-entry reason' do
      result = analyzer.analyze(signal_type: :ce, strategy_type: 'intraday')
      expect(result).to eq(proceed: false, reason: 'Late entry, theta risk')
    end
  end

  describe 'deep strike classification' do
    let(:option_chain) { { oc: { 100 => {} }, last_price: 100 } }
    let(:expiry) { Date.today.to_s }
    let(:spot) { 100.0 }
    let(:iv_rank) { 0.5 }

    before do
      allow(analyzer).to receive(:determine_atm_strike).and_return(100)
    end

    describe '#deep_itm_strike?' do
      context 'for calls' do
        it 'returns true when below 80% of ATM' do
          expect(analyzer.send(:deep_itm_strike?, 79, :ce)).to be(true)
        end

        it 'returns false at 80% boundary' do
          expect(analyzer.send(:deep_itm_strike?, 80, :ce)).to be(false)
        end
      end

      context 'for puts' do
        it 'returns true when above 120% of ATM' do
          expect(analyzer.send(:deep_itm_strike?, 121, :pe)).to be(true)
        end

        it 'returns false at 120% boundary' do
          expect(analyzer.send(:deep_itm_strike?, 120, :pe)).to be(false)
        end
      end
    end

    describe '#deep_otm_strike?' do
      context 'for calls' do
        it 'returns true when above 120% of ATM' do
          expect(analyzer.send(:deep_otm_strike?, 121, :ce)).to be(true)
        end

        it 'returns false at 120% boundary' do
          expect(analyzer.send(:deep_otm_strike?, 120, :ce)).to be(false)
        end
      end

      context 'for puts' do
        it 'returns true when below 80% of ATM' do
          expect(analyzer.send(:deep_otm_strike?, 79, :pe)).to be(true)
        end

        it 'returns false at 80% boundary' do
          expect(analyzer.send(:deep_otm_strike?, 80, :pe)).to be(false)
        end
      end
    end
  end
end
