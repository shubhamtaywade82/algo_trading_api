# frozen_string_literal: true

# Common market data methods shared between Instrument and Derivative models
module InstrumentHelper
  extend ActiveSupport::Concern

  # Prefer the stored generated column, which Postgres maintains from
  # (exchange, segment) and which the lookup indexes are built on, so this
  # cannot disagree with what a query matched. The case statement stays as the
  # fallback for records not loaded from the table.
  #
  # This concern is included after InstrumentHelpers, so it shadows that
  # module's identically named method — it has to do the same column check or
  # Instrument would silently lose it.
  def exchange_segment
    return self[:exchange_segment] if has_attribute?(:exchange_segment) && self[:exchange_segment].present?

    case [exchange.to_sym, segment.to_sym]
    when %i[nse index], %i[bse index] then 'IDX_I'
    when %i[nse equity] then 'NSE_EQ'
    when %i[bse equity] then 'BSE_EQ'
    when %i[nse derivatives] then 'NSE_FNO'
    when %i[bse derivatives] then 'BSE_FNO'
    when %i[nse currency] then 'NSE_CURRENCY'
    when %i[bse currency] then 'BSE_CURRENCY'
    when %i[mcx commodity] then 'MCX_COMM'
    else
      raise "Unsupported exchange and segment combination: #{exchange}, #{segment}"
    end
  end

  # Fetch Last Traded Price (LTP) from DhanHQ MarketFeed API
  def ltp
    Dhan::MarketDataService.new(self).ltp
  end

  # Fetch OHLC (Open, High, Low, Close) data from DhanHQ MarketFeed API
  def ohlc
    Dhan::MarketDataService.new(self).ohlc
  end

  # Fetch market depth/quote data from DhanHQ MarketFeed API
  def depth
    Dhan::MarketDataService.new(self).depth
  end
end
