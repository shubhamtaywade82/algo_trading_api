module MarketCalendar
  def self.market_holidays
    @market_holidays ||= AppSetting.fetch_array('market_holidays', default: [])
                                     .map { |d| Date.parse(d) }
  end

  def self.trading_day?(date)
    weekday = date.on_weekday?
    !market_holidays.include?(date) && weekday
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
