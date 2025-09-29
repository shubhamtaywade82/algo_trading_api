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
        to_date = Time.zone.today
        from_date = lookback_days.days.ago.to_date

        Dhanhq::API::Historical.intraday(
          securityId: instrument.security_id,
          exchangeSegment: instrument.exchange_segment,
          instrument: instrument.instrument_type,
          interval: interval,
          fromDate: from_date.iso8601,
          toDate: to_date.iso8601,
          oi: false
        )
      rescue StandardError => e
        Rails.logger.error { "[HistoricalDataFetcher] intraday failed – #{e.message}" }
        []
      end

      def daily(instrument, lookback_days: DEFAULT_DAILY_LOOKBACK_DAYS)
        to_date = Date.yesterday
        from_date = lookback_days.days.ago.to_date

        Dhanhq::API::Historical.daily(
          securityId: instrument.security_id,
          exchangeSegment: instrument.exchange_segment,
          instrument: instrument.instrument_type,
          fromDate: from_date.to_s,
          toDate: to_date.to_s,
          oi: false
        )
      rescue StandardError => e
        Rails.logger.error { "[HistoricalDataFetcher] daily failed – #{e.message}" }
        []
      end
    end
  end
end
