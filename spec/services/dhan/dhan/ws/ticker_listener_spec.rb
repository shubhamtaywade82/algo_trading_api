# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Dhan::Ws::TickerListener do
  let(:security_id) { '13' }
  let(:exchange_segment) { 'NSE_EQ' }
  let(:parsed_response) do
    {
      exchange: exchange_segment,
      security_id: security_id,
      ltp: 5971.0,
      last_quantity: 5,
      last_trade_time: '30/05/2025 15:58:45',
      volume: 296_253
    }
  end

  let(:market_feed_response) do
    {
      "data" => {
        exchange_segment => {
          security_id => {
            "last_price" => 5971,
            "last_quantity" => 5,
            "last_trade_time" => "30/05/2025 15:58:45",
            "volume" => 296253
          }
        }
      },
      "status" => "success"
    }
  end

  subject(:listener) { described_class.new }

  before { Rails.cache.clear }

  describe '#process_packet' do
    it 'stores LTP into Rails.cache correctly' do
      listener.process_packet(market_feed_response)

      cached_value = Rails.cache.read("ltp_#{security_id}")
      expect(cached_value).to eq(parsed_response[:ltp])
    end

    it 'stores full packet data if required' do
      listener.process_packet(market_feed_response)

      expect(Rails.cache.read("volume_#{security_id}")).to eq(parsed_response[:volume])
      expect(Rails.cache.read("last_trade_time_#{security_id}")).to eq(parsed_response[:last_trade_time])
    end
  end
end
