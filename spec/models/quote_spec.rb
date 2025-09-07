# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Quote, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:instrument) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:ltp) }
    it { is_expected.to validate_presence_of(:tick_time) }
  end

  describe 'store_accessor' do
    it 'allows access to oi metadata' do
      quote = build(:quote, metadata: { oi: 1000 })
      expect(quote.oi).to eq(1000)
    end

    it 'allows access to depth metadata' do
      quote = build(:quote, metadata: { depth: { bid: 100, ask: 101 } })
      expect(quote.depth).to eq({ 'bid' => 100, 'ask' => 101 })
    end
  end

  describe 'scopes' do
    let!(:instrument1) { create(:instrument, symbol_name: 'TCS', security_id: '11536') }
    let!(:instrument2) { create(:instrument, symbol_name: 'INFY', security_id: '408065') }
    let!(:old_quote) { create(:quote, tick_time: 2.hours.ago, instrument: instrument1) }
    let!(:recent_quote) { create(:quote, tick_time: 1.hour.ago, instrument: instrument2) }

    describe '.recent' do
      it 'orders quotes by tick_time descending' do
        quotes = Quote.recent
        expect(quotes.first).to eq(recent_quote)
        expect(quotes.last).to eq(old_quote)
      end
    end
  end

  describe '#formatted_quote' do
    let(:instrument) { create(:instrument, symbol_name: 'RELIANCE') }
    let(:quote) { build(:quote, instrument: instrument, ltp: 2500.50, volume: 1000, tick_time: Time.current) }

    it 'formats the quote for display' do
      formatted = quote.formatted_quote
      expect(formatted).to include('RELIANCE')
      expect(formatted).to include('2500.5')
      expect(formatted).to include('1000')
      expect(formatted).to include(Time.current.strftime('%H:%M:%S'))
    end
  end

  describe 'factory' do
    it 'creates a valid quote' do
      instrument = create(:instrument, symbol_name: 'TCS', security_id: '11536')
      quote = build(:quote, instrument: instrument)
      expect(quote).to be_valid
    end

    it 'creates a quote with required ltp and tick_time' do
      instrument = create(:instrument, symbol_name: 'TCS', security_id: '11536')
      quote = create(:quote, instrument: instrument)
      expect(quote.ltp).to be_present
      expect(quote.tick_time).to be_present
    end
  end
end
