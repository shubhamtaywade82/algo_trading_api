module MarketCalendar
  MARKET_HOLIDAYS = [
    # 2025 Market Holidays
    Date.new(2025, 2, 26),  # Mahashivratri
    Date.new(2025, 3, 14),  # Holi
    Date.new(2025, 3, 31),  # Id-Ul-Fitr (Ramadan Eid)
    Date.new(2025, 4, 10),  # Shri Mahavir Jayanti
    Date.new(2025, 4, 14),  # Dr. Baba Saheb Ambedkar Jayanti
    Date.new(2025, 4, 18),  # Good Friday
    Date.new(2025, 5, 1),   # Maharashtra Day
    Date.new(2025, 8, 15),  # Independence Day / Parsi New Year
    Date.new(2025, 8, 27),  # Shri Ganesh Chaturthi
    Date.new(2025, 10, 2),  # Mahatma Gandhi Jayanti/Dussehra
    Date.new(2025, 10, 21), # Diwali Laxmi Pujan
    Date.new(2025, 10, 22), # Balipratipada
    Date.new(2025, 11, 5),  # Prakash Gurpurb Sri Guru Nanak Dev
    Date.new(2025, 12, 25)  # Christmas
  ].freeze

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

  def self.trading_days_between(from_date, to_date)
    (from_date..to_date).select { |date| trading_day?(date) }
  end
end
