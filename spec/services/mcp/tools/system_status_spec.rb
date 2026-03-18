# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mcp::Tools::SystemStatus do
  include ActiveSupport::Testing::TimeHelpers

  describe '.execute' do
    let(:now) { Time.zone.parse('2026-03-18 09:16:00') }
    let(:market_logger) { Rails.logger }

    before do
      allow(MarketCalendar).to receive(:trading_day?).and_return(true)
      allow(Orders::Gateway).to receive(:place_order_enabled?).and_return(true)
    end

    it 'returns market_open true inside trading window' do
      allow(Positions::ActiveCache).to receive(:all_positions).and_return([{}, {}])

      travel_to(now) do
        result = described_class.execute({})
        expect(result[:market_open]).to be true
        expect(result[:active_positions]).to eq(2)
        expect(result[:allowed_to_trade]).to be true
        expect(result[:place_order_flag]).to be true
      end
    end

    it 'returns market_open false outside trading window' do
      allow(MarketCalendar).to receive(:trading_day?).and_return(true)
      allow(Positions::ActiveCache).to receive(:all_positions).and_return([{}, {}, {}])

      travel_to(Time.zone.parse('2026-03-18 08:59:00')) do
        result = described_class.execute({})
        expect(result[:market_open]).to be false
        expect(result[:allowed_to_trade]).to be false
      end
    end
  end
end

