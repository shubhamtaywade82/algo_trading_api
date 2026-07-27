# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Dhan::MarketDataService do
  subject(:service) { described_class.new(instrument) }

  let(:instrument) { instance_double(Instrument, security_id: '13', exchange_segment: 'IDX_I', resolve_instrument_code: 'INDEX') }

  describe '#intraday_ohlc' do
    it 'retries after forcing token refresh when DH-906 invalid token error occurs' do
      attempts = 0
      allow(DhanHQ::Models::HistoricalData).to receive(:intraday) do
        attempts += 1
        raise StandardError, 'DH-906: Invalid Token' if attempts == 1

        { 'start_Time' => [1_700_000_000], 'open' => [23_000.0], 'high' => [23_100.0], 'low' => [22_950.0], 'close' => [23_050.0],
          'volume' => [1000] }
      end

      expect(Dhan::TokenManager).to receive(:force_refresh!).once

      result = service.intraday_ohlc
      expect(result).to include(:open, :high, :low, :close)
      expect(attempts).to eq(2)
    end
  end
end
