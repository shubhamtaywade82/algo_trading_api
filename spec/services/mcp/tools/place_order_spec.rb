# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mcp::Tools::PlaceOrder do
  describe '.execute' do
    let(:payload_result) do
      {
        dry_run: true,
        blocked: true,
        message: 'PLACE_ORDER is not true; order not sent.',
        order_id: nil
      }
    end

    before do
      allow(Orders::Manager).to receive(:place_order).and_return(payload_result)
    end

    it 'builds payload and delegates to Orders::Manager.place_order' do
      result = described_class.execute(
        'security_id' => '1333',
        'exchange_segment' => 'NSE_FNO',
        'transaction_type' => 'BUY',
        'quantity' => 1,
        'product_type' => 'INTRADAY',
        'order_type' => 'LIMIT',
        'price' => 100.5
      )

      expect(result[:dry_run]).to be true
    end

    it 'errors if price is missing for LIMIT' do
      result = described_class.execute(
        'security_id' => '1333',
        'exchange_segment' => 'NSE_FNO',
        'transaction_type' => 'BUY',
        'quantity' => 1,
        'product_type' => 'INTRADAY',
        'order_type' => 'LIMIT'
      )
      expect(result[:error]).to include('price is required')
    end
  end
end

