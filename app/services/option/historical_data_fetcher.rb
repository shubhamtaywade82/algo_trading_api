# frozen_string_literal: true

module Option
  class HistoricalDataFetcher
    DEFAULT_INTRADAY_INTERVAL = '5'
    DEFAULT_INTRADAY_LOOKBACK_DAYS = 5
    DEFAULT_DAILY_LOOKBACK_DAYS = 45

    class << self
      def for_strategy(instrument, strategy_type: nil)
        strategy = strategy_type.to_s.presence || 'intraday'
        strategy == 'intraday' ? intraday(instrument) : daily(instrument)
      end

      def intraday(instrument, interval: DEFAULT_INTRADAY_INTERVAL, lookback_days: DEFAULT_INTRADAY_LOOKBACK_DAYS)
        to_date = MarketCalendar.today_or_last_trading_day
        from_date = MarketCalendar.from_date_for_last_n_trading_days(to_date, lookback_days)

        instrument_code = instrument.respond_to?(:resolve_instrument_code) ? instrument.resolve_instrument_code : instrument.instrument_before_type_cast
        DhanHQ::Models::HistoricalData.intraday(
          security_id: instrument.security_id,
          exchange_segment: instrument.exchange_segment,
          instrument: instrument_code,
          interval: interval,
          from_date: from_date.to_s,
          to_date: to_date.to_s,
          oi: false
        )
      rescue StandardError => e
        Rails.logger.error { "[HistoricalDataFetcher] intraday failed – #{e.message}" }
        []
      end

      def daily(instrument, lookback_days: DEFAULT_DAILY_LOOKBACK_DAYS)
        to_date = MarketCalendar.last_trading_day(from: Time.zone.today - 1)
        from_date = MarketCalendar.last_trading_day_before(to_date, calendar_days: lookback_days)

        instrument_code = instrument.respond_to?(:resolve_instrument_code) ? instrument.resolve_instrument_code : instrument.instrument_before_type_cast
        DhanHQ::Models::HistoricalData.daily(
          security_id: instrument.security_id,
          exchange_segment: instrument.exchange_segment,
          instrument: instrument_code,
          from_date: from_date.to_s,
          to_date: to_date.to_s,
          oi: false
        )
      rescue StandardError => e
        Rails.logger.error { "[HistoricalDataFetcher] daily failed – #{e.message}" }
        []
      end
    end
  end
end
