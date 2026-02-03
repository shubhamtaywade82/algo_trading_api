# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MarketCalendar do
  # Fixed weekdays (Jan 2026: 26=Mon, 27=Tue, 28=Wed, 29=Thu, 30=Fri, 31=Sat)
  let(:monday)    { Date.new(2026, 1, 26) }
  let(:tuesday)   { Date.new(2026, 1, 27) }
  let(:wednesday) { Date.new(2026, 1, 28) }
  let(:friday)   { Date.new(2026, 1, 30) }
  let(:saturday) { Date.new(2026, 1, 31) }
  let(:sunday)   { Date.new(2026, 2, 1) }
  # Holiday in MARKET_HOLIDAYS
  let(:christmas_2025) { Date.new(2025, 12, 25) }
  let(:holi_2026)     { Date.new(2026, 3, 4) }

  describe '.trading_day?' do
    context 'on weekdays (no holiday)' do
      it 'returns true for Monday through Friday' do
        expect(described_class.trading_day?(monday)).to be true
        expect(described_class.trading_day?(tuesday)).to be true
        expect(described_class.trading_day?(wednesday)).to be true
        expect(described_class.trading_day?(friday)).to be true
      end
    end

    context 'on weekends' do
      it 'returns false for Saturday' do
        expect(described_class.trading_day?(saturday)).to be false
      end

      it 'returns false for Sunday' do
        expect(described_class.trading_day?(sunday)).to be false
      end
    end

    context 'on market holidays' do
      it 'returns false for Christmas 2025' do
        expect(described_class.trading_day?(christmas_2025)).to be false
      end

      it 'returns false for Holi 2026' do
        expect(described_class.trading_day?(holi_2026)).to be false
      end
    end

    context 'when given Time or DateTime' do
      it 'normalizes to date and returns true for a weekday' do
        expect(described_class.trading_day?(tuesday.to_time)).to be true
      end

      it 'returns false for Saturday as Time' do
        expect(described_class.trading_day?(saturday.to_time)).to be false
      end
    end

    context 'edge cases' do
      it 'returns false for nil (no on_weekday?)' do
        expect(described_class.trading_day?(nil)).to be false
      end
    end
  end

  describe '.last_trading_day' do
    context 'when from is a weekday (trading day)' do
      it 'returns the same date' do
        expect(described_class.last_trading_day(from: tuesday)).to eq(tuesday)
      end
    end

    context 'when from is Saturday' do
      it 'returns the previous Friday' do
        expect(described_class.last_trading_day(from: saturday)).to eq(friday)
      end
    end

    context 'when from is Sunday' do
      it 'returns the previous Friday' do
        expect(described_class.last_trading_day(from: sunday)).to eq(friday)
      end
    end

    context 'when from is Monday' do
      it 'returns Monday' do
        expect(described_class.last_trading_day(from: monday)).to eq(monday)
      end
    end

    context 'when from is a holiday' do
      it 'returns the previous trading day' do
        expect(described_class.last_trading_day(from: christmas_2025)).to eq(Date.new(2025, 12, 24))
      end
    end

    context 'when from is day after holiday (e.g. Friday after Thursday holiday)' do
      it 'returns the given date if it is a trading day' do
        # Dec 26, 2025 is Friday
        expect(described_class.last_trading_day(from: Date.new(2025, 12, 26))).to eq(Date.new(2025, 12, 26))
      end
    end
  end

  describe '.today_or_last_trading_day' do
    # Canonical "to_date" for market data: always today (calendar) when it is a trading day,
    # else the most recent trading day (e.g. Friday on weekend).
    context 'when today is a weekday (trading day)' do
      it 'returns today (Date.today)' do
        travel_to tuesday do
          expect(described_class.today_or_last_trading_day).to eq(Time.zone.today)
          expect(described_class.today_or_last_trading_day).to eq(tuesday)
        end
      end
    end

    context 'when today is Saturday' do
      it 'returns previous Friday (last trading day)' do
        travel_to saturday do
          expect(described_class.today_or_last_trading_day).to eq(friday)
        end
      end
    end

    context 'when today is Sunday' do
      it 'returns previous Friday (last trading day)' do
        travel_to sunday do
          expect(described_class.today_or_last_trading_day).to eq(friday)
        end
      end
    end

    context 'when today is a market holiday' do
      it 'returns previous trading day' do
        travel_to christmas_2025 do
          expect(described_class.today_or_last_trading_day).to eq(Date.new(2025, 12, 24))
        end
      end
    end

    it 'always returns a trading day (weekday and not in MARKET_HOLIDAYS)' do
      [tuesday, saturday, sunday, christmas_2025].each do |day|
        travel_to day do
          result = described_class.today_or_last_trading_day
          expect(described_class.trading_day?(result)).to be true
        end
      end
    end
  end

  describe '.from_date_for_last_n_trading_days' do
    context 'when n is 1' do
      it 'returns to_date' do
        expect(described_class.from_date_for_last_n_trading_days(friday, 1)).to eq(friday)
      end
    end

    context 'when n is 2' do
      it 'returns the previous trading day' do
        expect(described_class.from_date_for_last_n_trading_days(friday, 2)).to eq(wednesday)
      end

      it 'when to_date is Monday returns previous Friday' do
        expect(described_class.from_date_for_last_n_trading_days(monday, 2)).to eq(friday)
      end
    end

    context 'when n is 5' do
      it 'returns the date 4 trading days before to_date' do
        # Fri 30 -> Thu 29 -> Wed 28 -> Tue 27 -> Mon 26
        expect(described_class.from_date_for_last_n_trading_days(friday, 5)).to eq(monday)
      end
    end

    context 'when to_date is Saturday (non-trading)' do
      it 'uses Saturday as reference and steps back to Friday then Thursday' do
        # Spec does not require to_date to be trading; implementation steps back from to_date.
        # So from_date_for_last_n_trading_days(saturday, 2) => last_trading_day(from: saturday-1) => friday.
        expect(described_class.from_date_for_last_n_trading_days(saturday, 2)).to eq(friday)
      end
    end
  end

  describe '.last_trading_day_before' do
    context 'when reference_date is a weekday' do
      it 'with calendar_days 0 returns reference_date' do
        expect(described_class.last_trading_day_before(tuesday, calendar_days: 0)).to eq(tuesday)
      end

      it 'with calendar_days 2 returns 2 calendar days back, adjusted to trading day' do
        # Tuesday - 2 = Sunday -> last trading day = Friday
        expect(described_class.last_trading_day_before(tuesday, calendar_days: 2)).to eq(friday)
      end

      it 'with calendar_days 10 returns last trading day on or before (ref - 10)' do
        # Friday Jan 30 - 10 = Jan 20 (Monday)
        expect(described_class.last_trading_day_before(friday, calendar_days: 10)).to eq(Date.new(2026, 1, 20))
      end
    end

    context 'when reference_date is Saturday' do
      it 'with calendar_days 1 returns Friday (ref - 1 = Friday)' do
        expect(described_class.last_trading_day_before(saturday, calendar_days: 1)).to eq(friday)
      end
    end
  end
end
