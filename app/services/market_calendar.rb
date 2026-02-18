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
    Date.new(2025, 12, 25), # Christmas
    # 2026 Market Holidays
    Date.new(2026, 2, 17),  # Mahashivratri
    Date.new(2026, 3, 4),   # Holi
    Date.new(2026, 3, 24),  # Id-Ul-Fitr
    Date.new(2026, 4, 3),   # Mahavir Jayanti / Good Friday
    Date.new(2026, 4, 14),  # Dr. Ambedkar Jayanti
    Date.new(2026, 5, 1),   # Maharashtra Day
    Date.new(2026, 8, 15),  # Independence Day
    Date.new(2026, 8, 17),  # Ganesh Chaturthi (approx)
    Date.new(2026, 10, 2),  # Gandhi Jayanti
    Date.new(2026, 10, 20), # Diwali (approx)
    Date.new(2026, 10, 21), # Balipratipada (approx)
    Date.new(2026, 11, 24), # Guru Nanak Jayanti (approx)
    Date.new(2026, 12, 25)  # Christmas
  ].freeze

  def self.trading_day?(date)
    return false unless date.respond_to?(:on_weekday?)

    date = date.to_date if date.respond_to?(:to_date)
    date.on_weekday? && MARKET_HOLIDAYS.exclude?(date)
  end

  # Returns the most recent trading day on or before +from+.
  # Weekdays: returns +from+ if it's a trading day, else previous trading day.
  # Weekends/holidays: steps back until a trading day.
  def self.last_trading_day(from: Time.zone.today)
    return Time.zone.today if from.blank?

    date = from.respond_to?(:to_date) ? from.to_date : from
    return Time.zone.today if date.blank?

    date -= 1 until trading_day?(date)
    date.presence || Time.zone.today
  end

  # Today if it's a trading day; otherwise the most recent trading day (e.g. Friday on weekend).
  def self.today_or_last_trading_day
    today = Time.zone.today
    trading_day?(today) ? today : last_trading_day(from: today)
  end

  # Returns +from_date+ such that the range [from_date, to_date] (inclusive) spans exactly +n+ trading days.
  # When n == 1, returns to_date. Use for intraday/historical "last n trading days".
  def self.from_date_for_last_n_trading_days(to_date, n)
    return Time.zone.today if to_date.blank?

    to_d = to_date.respond_to?(:to_date) ? to_date.to_date : to_date
    return Time.zone.today if to_d.blank?
    return to_d if n <= 1

    date = to_d
    (n - 1).times do
      break unless date.respond_to?(:-)

      date = last_trading_day(from: date - 1)
    end
    date.presence || Time.zone.today
  end

  # Returns the last trading day on or before (reference_date - calendar_days).
  # Use when you want "about N calendar days ago" but must land on a trading day.
  def self.last_trading_day_before(reference_date, calendar_days: 0)
    ref = reference_date.respond_to?(:to_date) ? reference_date.to_date : reference_date
    last_trading_day(from: ref - calendar_days)
  end
end
