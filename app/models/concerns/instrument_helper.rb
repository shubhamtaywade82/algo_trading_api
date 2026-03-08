# frozen_string_literal: true

# Common market data methods shared between Instrument and Derivative models
module InstrumentHelper
  extend ActiveSupport::Concern

  # Generate `exchange_segment` dynamically based on exchange and segment enums
  def exchange_segment
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
