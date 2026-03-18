# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Orders::PlaceOrderGuard do
  subject(:guard_call) { described_class.call(payload, logger: Rails.logger, source: 'spec') }

  let(:payload) do
    {
      security_id: '1333',
      exchange_segment: 'NSE_FNO',
      transaction_type: 'BUY',
      quantity: 1,
      product_type: 'INTRADAY',
      order_type: 'LIMIT',
      price: 100.0
    }
  end

  describe 'validation gates' do
    it 'blocks when market is closed' do
      now = Time.zone.parse('2026-03-18 20:00:00')
      travel_to(now) do
        allow(MarketCalendar).to receive(:trading_day?).and_return(false)
        allow(Positions::ActiveCache).to receive(:all_positions).and_return([])

        expect { guard_call }.to raise_error(/Trading not allowed/)
      end
    end

    it 'blocks when spread is above threshold' do
      now = Time.zone.parse('2026-03-18 10:00:00')
      travel_to(now) do
        allow(MarketCalendar).to receive(:trading_day?).and_return(true)
        allow(Positions::ActiveCache).to receive(:all_positions).and_return([instance_double('Position')])

        instrument_double = instance_double(Instrument)
        derivative = instance_double(
          Derivative,
          exchange_segment: 'NSE_FNO',
          expiry_date: Date.iso8601('2026-03-26'),
          strike_price: 22_450.0,
          option_type: 'CE',
          instrument: instrument_double
        )

        option_chain = {
          oc: {
            '22450.000000' => {
              'ce' => {
                'oi' => 2_000,
                'volume' => 600,
                'last_price' => 100.0,
                'top_bid_price' => 95.0,
                'top_ask_price' => 105.0
              }
            }
          }
        }
        allow(instrument_double).to receive(:fetch_option_chain).with(Date.iso8601('2026-03-26')).and_return(option_chain)

        allow(Derivative).to receive(:find_by)
          .with(security_id: '1333')
          .and_return(derivative)

        prev_value = ENV['EXECUTION_MAX_SPREAD_PCT']
        ENV['EXECUTION_MAX_SPREAD_PCT'] = '0.05'

        begin
          expect { guard_call }.to raise_error(/Spread too high/)
        ensure
          ENV['EXECUTION_MAX_SPREAD_PCT'] = prev_value
        end
      end
    end
  end
end

