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
    payload = { exchange_segment => [security_id.to_i] }
    response = DhanHQ::Models::MarketFeed.ltp(payload)

    # Extract last_price from nested response structure
    # Response format: {"data" => {"EXCHANGE_SEGMENT" => {"security_id" => {"last_price" => value}}}, "status" => "success"}
    data = response[:data] || response['data'] || response
    return nil unless data

    segment_data = data[exchange_segment] || data[exchange_segment.to_sym]
    return nil unless segment_data

    security_data = segment_data[security_id.to_s] || segment_data[security_id.to_i]
    return nil unless security_data

    security_data[:last_price] || security_data['last_price'] || security_data[:ltp] || security_data['ltp']
  rescue StandardError => e
    Rails.logger.error("Failed to fetch LTP for #{self.class.name} #{security_id}: #{e.message}")
    nil
  end

  # Fetch OHLC (Open, High, Low, Close) data from DhanHQ MarketFeed API
  def ohlc
    payload = { exchange_segment => [security_id.to_i] }
    response = DhanHQ::Models::MarketFeed.ohlc(payload)

    # Extract data from nested response structure
    data = response[:data] || response['data'] || response
    return nil unless data

    segment_data = data[exchange_segment] || data[exchange_segment.to_sym]
    return nil unless segment_data

    segment_data[security_id.to_s] || segment_data[security_id.to_i]
  rescue StandardError => e
    Rails.logger.error("Failed to fetch OHLC for #{self.class.name} #{security_id}: #{e.message}")
    nil
  end

  # Fetch market depth/quote data from DhanHQ MarketFeed API
  def depth
    payload = { exchange_segment => [security_id.to_i] }
    response = DhanHQ::Models::MarketFeed.quote(payload)

    # Extract data from nested response structure
    data = response[:data] || response['data'] || response
    return nil unless data

    segment_data = data[exchange_segment] || data[exchange_segment.to_sym]
    return nil unless segment_data

    segment_data[security_id.to_s] || segment_data[security_id.to_i]
  rescue StandardError => e
    Rails.logger.error("Failed to fetch Depth for #{self.class.name} #{security_id}: #{e.message}")
    nil
  end
end

