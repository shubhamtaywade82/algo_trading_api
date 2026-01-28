# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DhanHQ::WS::WebsocketPacketParser do
  let(:binary_data) { Rails.root.join('spec/fixtures/ws/full_packet_13.bin').binread }
  let(:parsed) { described_class.new(binary_data).parse }

  it 'parses FullPacket correctly for security_id 13' do
    expect(parsed[:feed_response_code]).to eq(8)
    expect(parsed[:security_id]).to eq(13)
    expect(parsed[:ltp]).to be_within(0.5).of(5971.0)
    expect(parsed[:atp]).to be_within(0.5).of(6011.05)
    expect(parsed[:last_trade_qty]).to eq(5)
    expect(parsed[:volume]).to eq(296_253)
    expect(parsed[:total_sell_qty]).to eq(289)
    expect(parsed[:total_buy_qty]).to eq(0)
    expect(parsed[:day_open]).to be_within(0.5).of(6080.0)
    expect(parsed[:day_close]).to be_within(0.5).of(5971.0)
    expect(parsed[:day_high]).to be_within(0.5).of(6118.0)
    expect(parsed[:day_low]).to be_within(0.5).of(5945.5)

    depth = parsed[:market_depth]
    expect(depth.size).to eq(5)

    # Gem returns BinData records (struct-like)
    expect(depth[0].ask_price).to be_within(0.5).of(5971.0)
    expect(depth[0].ask_quantity).to eq(289)
    expect(depth[0].no_of_ask_orders).to eq(8)

    depth[1..4].each do |level|
      expect(level.ask_price).to eq(0.0)
      expect(level.ask_quantity).to eq(0)
    end
  end
end
