# frozen_string_literal: true

# Helper Module
module MarketFeedHelper
  def fetch_ltp
    fetch_market_feed_data(:ltp)
  end

  def fetch_ohlc
    fetch_market_feed_data(:ohlc)
  end

  def fetch_depth
    fetch_market_feed_data(:quote)
  end

  private

  def fetch_market_feed_data(method)
    response = Dhanhq::API::MarketFeed.send(method, exch_segment_enum)
    response['status'] == 'success' ? response.dig('data', exchange_segment, security_id.to_s) : nil
  rescue StandardError => e
    Rails.logger.error("Failed to fetch #{method.to_s.upcase} for #{self.class.name} #{id}: #{e.message}")
    nil
  end

  def exch_segment_enum
    { exchange_segment => [security_id.to_i] }
  end
end
