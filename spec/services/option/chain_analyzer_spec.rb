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
      expect(result[:reason]).to include('IV rank outside range')
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
      expect(result[:proceed]).to eq(false)
      expect(result[:reason]).to include('Late entry, theta risk')
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

  describe '#get_strike_filter_summary' do
    let(:expiry) { Date.today.to_s }
    let(:spot) { 20_000.0 }
    let(:iv_rank) { 0.1 }
    let(:strike_step) { 50 }
    let(:atm_strike) { 20_000.0 }

    let(:option_chain) do
      {
        last_price: spot,
        oc: {
          format('%.6f', atm_strike) => {
            'ce' => {
              'last_price' => 5.0,
              'implied_volatility' => 0.18,
              'oi' => 1_000,
              'volume' => 200,
              'previous_close_price' => 6.0,
              'previous_volume' => 150,
              'previous_oi' => 900,
              'greeks' => {
                'delta' => 0.1,
                'gamma' => 0.02,
                'theta' => -0.5,
                'vega' => 0.8
              }
            }
          },
          format('%.6f', atm_strike + (strike_step * 40)) => {
            'ce' => {
              'last_price' => 1.0,
              'implied_volatility' => 0.12,
              'oi' => 500,
              'volume' => 50,
              'previous_close_price' => 1.1,
              'previous_volume' => 40,
              'previous_oi' => 450,
              'greeks' => {
                'delta' => 0.05,
                'gamma' => 0.01,
                'theta' => -0.2,
                'vega' => 0.3
              }
            }
          },
          format('%.6f', atm_strike + (strike_step * 2)) => {
            'ce' => {
              'last_price' => 0,
              'implied_volatility' => 0,
              'oi' => 0,
              'volume' => 0,
              'previous_close_price' => 0,
              'previous_volume' => 0,
              'previous_oi' => 0,
              'greeks' => {
                'delta' => 0,
                'gamma' => 0,
                'theta' => 0,
                'vega' => 0
              }
            }
          }
        }
      }
    end

    subject(:analyzer) do
      described_class.new(
        option_chain,
        expiry: expiry,
        underlying_spot: spot,
        iv_rank: iv_rank,
        historical_data: [],
        strike_step: strike_step
      )
    end

    before do
      allow(analyzer).to receive(:determine_atm_strike).and_return(atm_strike)
      allow(analyzer).to receive(:gather_filtered_strikes).and_return([])
      travel_to(Time.zone.local(2025, 1, 1, 11, 0, 0))
    end

    after do
      travel_back
    end

    it 'skips inactive and deep strikes when building failure details' do
      summary = analyzer.send(:get_strike_filter_summary, :ce)

      detailed_entries = summary[:filters_applied].select { |entry| entry.is_a?(Hash) }

      expect(detailed_entries.size).to eq(1)
      expect(detailed_entries.first[:strike_price]).to eq(atm_strike)
      expect(detailed_entries.first[:reasons]).to include(a_string_matching(/Delta low/))

      reported_strikes = detailed_entries.map { |entry| entry[:strike_price] }
      expect(reported_strikes).not_to include(atm_strike + (strike_step * 40))
    end
  end
end
