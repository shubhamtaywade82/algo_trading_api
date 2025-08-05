module MarketCalendar
  MARKET_HOLIDAYS = [
    # Add static or API-fetched holiday dates here
    Date.new(2025, 8, 15)
    # ...
  ]

  def self.trading_day?(date)
    weekday = date.on_weekday?
    !MARKET_HOLIDAYS.include?(date) && weekday
  end

  def self.last_trading_day(from: Time.zone.today)
    date = from
    date -= 1 until trading_day?(date)
    date
  end

  def self.today_or_last_trading_day
    trading_day?(Time.zone.today) ? Time.zone.today : last_trading_day
  end
end
