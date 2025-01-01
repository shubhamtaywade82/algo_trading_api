class MarketFeedSubscriptionService
  def self.subscribe_to_equities
    instruments = Instrument.equities.limit(1000).pluck(:exchange_segment, :security_id)
    formatted_instruments = instruments.map do |segment, id|
      { exchange_segment: segment, security_id: id }
    end

    live_feed = LiveMarketFeed.new
    live_feed.subscribe_to_instruments(formatted_instruments)
  end
end
