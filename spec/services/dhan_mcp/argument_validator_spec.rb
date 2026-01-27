# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DhanMcp::ArgumentValidator, type: :service, mcp: true do
  describe '.symbolize' do
    it 'converts string keys to symbols' do
      result = described_class.symbolize('exchange_segment' => 'NSE_EQ', 'symbol' => 'RELIANCE')
      expect(result).to eq(exchange_segment: 'NSE_EQ', symbol: 'RELIANCE')
    end

    it 'returns empty hash for nil' do
      expect(described_class.symbolize(nil)).to eq({})
    end

    it 'returns empty hash for non-hash' do
      expect(described_class.symbolize('foo')).to eq({})
    end
  end

  describe '.validate' do
    describe 'tools with no arguments' do
      %w[get_holdings get_positions get_fund_limits get_order_list get_edis_inquiry].each do |tool|
        context "for #{tool}" do
          it 'returns nil when args are empty' do
            expect(described_class.validate(tool, {})).to be_nil
          end

          it 'returns error when extra keys are passed' do
            err = described_class.validate(tool, { foo: 'bar' })
            expect(err).to include('Unexpected argument(s)')
            expect(err).to include('foo')
          end
        end
      end
    end

    describe 'get_order_by_id' do
      it 'returns error when order_id is missing' do
        expect(described_class.validate('get_order_by_id', {})).to eq('Missing required argument(s): order_id')
      end

      it 'returns error when order_id is blank' do
        expect(described_class.validate('get_order_by_id', { order_id: '  ' })).to eq('order_id must be non-empty.')
      end

      it 'returns nil when order_id is present and non-empty' do
        expect(described_class.validate('get_order_by_id', { order_id: 'ORD123' })).to be_nil
      end
    end

    describe 'get_order_by_correlation_id' do
      it 'returns error when correlation_id is missing' do
        expect(described_class.validate('get_order_by_correlation_id', {})).to eq('Missing required argument(s): correlation_id')
      end

      it 'returns nil when correlation_id is present' do
        expect(described_class.validate('get_order_by_correlation_id', { correlation_id: 'ref-1' })).to be_nil
      end
    end

    describe 'get_trade_book' do
      it 'returns error when order_id is missing' do
        expect(described_class.validate('get_trade_book', {})).to eq('Missing required argument(s): order_id')
      end

      it 'returns nil when order_id is present' do
        expect(described_class.validate('get_trade_book', { order_id: 'ORD123' })).to be_nil
      end
    end

    describe 'get_instrument, get_market_ohlc, get_expiry_list' do
      %w[get_instrument get_market_ohlc get_expiry_list].each do |tool|
        context "for #{tool}" do
          it 'returns error when exchange_segment is missing' do
            err = described_class.validate(tool, { symbol: 'RELIANCE' })
            expect(err).to eq('Missing required argument(s): exchange_segment')
          end

          it 'returns error when symbol is missing' do
            err = described_class.validate(tool, { exchange_segment: 'NSE_EQ' })
            expect(err).to eq('Missing required argument(s): symbol')
          end

          it 'returns error when exchange_segment is invalid' do
            err = described_class.validate(tool, { exchange_segment: 'INVALID', symbol: 'RELIANCE' })
            expect(err).to include('exchange_segment must be one of:')
            expect(err).to include('NSE_EQ')
          end

          it 'returns nil when both are valid' do
            expect(described_class.validate(tool, { exchange_segment: 'NSE_EQ', symbol: 'RELIANCE' })).to be_nil
          end
        end
      end
    end

    describe 'get_trade_history' do
      let(:today) { Time.zone.today }
      let(:last_trading_day) { MarketCalendar.last_trading_day(from: today - 1) }

      it 'returns error when from_date or to_date is missing' do
        expect(described_class.validate('get_trade_history', {})).to include('Missing required argument(s)')
        expect(described_class.validate('get_trade_history', { from_date: today.to_s })).to include('to_date')
      end

      it 'returns error when to_date is not today' do
        err = described_class.validate('get_trade_history', {
          from_date: (today - 2).to_s,
          to_date: (today - 1).to_s
        })
        expect(err).to eq("to_date must be today (#{today}).")
      end

      it 'returns error when from_date is not the last trading day before to_date' do
        err = described_class.validate('get_trade_history', {
          from_date: (today - 2).to_s,
          to_date: today.to_s
        })
        expect(err).to eq("from_date must be the last trading day before to_date (#{last_trading_day}).")
      end

      it 'returns nil when to_date is today and from_date is last trading day' do
        expect(described_class.validate('get_trade_history', {
          from_date: last_trading_day.to_s,
          to_date: today.to_s
        })).to be_nil
      end

      it 'returns error for invalid date format' do
        err = described_class.validate('get_trade_history', { from_date: 'not-a-date', to_date: today.to_s })
        expect(err).to eq('from_date must be YYYY-MM-DD.')
      end

      it 'returns error when page_number is negative' do
        err = described_class.validate('get_trade_history', {
          from_date: last_trading_day.to_s,
          to_date: today.to_s,
          page_number: -1
        })
        expect(err).to eq('page_number must be a non-negative integer.')
      end

      it 'returns nil when page_number is 0 or positive' do
        expect(described_class.validate('get_trade_history', {
          from_date: last_trading_day.to_s,
          to_date: today.to_s,
          page_number: 0
        })).to be_nil
      end
    end

    describe 'get_historical_daily_data' do
      let(:today) { Time.zone.today }
      let(:last_trading_day) { MarketCalendar.last_trading_day(from: today - 1) }

      it 'returns error when required args are missing' do
        expect(described_class.validate('get_historical_daily_data', {})).to include('Missing required argument(s)')
      end

      it 'returns error when to_date is not today or from_date is not last trading day' do
        err = described_class.validate('get_historical_daily_data', {
          exchange_segment: 'NSE_EQ',
          symbol: 'RELIANCE',
          from_date: (today - 3).to_s,
          to_date: today.to_s
        })
        expect(err).to include('from_date must be the last trading day')
      end

      it 'returns nil when segment, symbol and date range are valid' do
        expect(described_class.validate('get_historical_daily_data', {
          exchange_segment: 'NSE_EQ',
          symbol: 'RELIANCE',
          from_date: last_trading_day.to_s,
          to_date: today.to_s
        })).to be_nil
      end
    end

    describe 'get_intraday_minute_data' do
      let(:today) { Time.zone.today }
      let(:last_trading_day) { MarketCalendar.last_trading_day(from: today - 1) }

      it 'returns error when interval is invalid' do
        err = described_class.validate('get_intraday_minute_data', {
          exchange_segment: 'NSE_EQ',
          symbol: 'RELIANCE',
          from_date: last_trading_day.to_s,
          to_date: today.to_s,
          interval: '99'
        })
        expect(err).to eq('interval must be one of: 1, 5, 15, 25, 60.')
      end

      it 'returns nil when interval is valid' do
        expect(described_class.validate('get_intraday_minute_data', {
          exchange_segment: 'NSE_EQ',
          symbol: 'RELIANCE',
          from_date: last_trading_day.to_s,
          to_date: today.to_s,
          interval: '5'
        })).to be_nil
      end

      it 'returns error when date range is invalid' do
        err = described_class.validate('get_intraday_minute_data', {
          exchange_segment: 'NSE_EQ',
          symbol: 'RELIANCE',
          from_date: (today - 2).to_s,
          to_date: today.to_s
        })
        expect(err).to include('from_date must be the last trading day')
      end
    end

    describe 'get_option_chain' do
      it 'returns error when expiry format is invalid' do
        err = described_class.validate('get_option_chain', {
          exchange_segment: 'NSE_FNO',
          symbol: 'NIFTY',
          expiry: 'invalid'
        })
        expect(err).to eq('expiry must be YYYY-MM-DD.')
      end

      it 'returns nil when all args are valid' do
        expect(described_class.validate('get_option_chain', {
          exchange_segment: 'NSE_FNO',
          symbol: 'NIFTY',
          expiry: '2025-01-30'
        })).to be_nil
      end
    end

    describe 'unknown tool' do
      it 'returns nil' do
        expect(described_class.validate('unknown_tool', { foo: 'bar' })).to be_nil
      end
    end
  end
end
