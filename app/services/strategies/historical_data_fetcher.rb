# frozen_string_literal: true

module Strategies
  class HistoricalDataFetcher
    def initialize(security_id, exchange_segment, from_date, to_date)
      @security_id = security_id
      @exchange_segment = exchange_segment
      @from_date = from_date
      @to_date = to_date
    end

    def fetch
      DhanHQ::HistoricalData.new(
        security_id: @security_id,
        exchange_segment: @exchange_segment,
        from_date: @from_date,
        to_date: @to_date
      ).fetch_data
    end
  end
end
