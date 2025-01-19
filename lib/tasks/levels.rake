# frozen_string_literal: true

namespace :levels do
  desc 'Update daily and weekly levels for all instruments'
  task update: :environment do
    Instrument.nse.where(underlying_symbol: 'RELIANCE').find_each do |instrument|
      Rails.logger.debug { "Processing instrument: #{instrument.symbol_name}" }

      # Calculate dates for daily levels
      daily_from_date, daily_to_date = calculate_daily_dates
      Rails.logger.debug { "Daily Levels: From #{daily_from_date} To #{daily_to_date}" }

      LevelService.new(
        instrument.id,
        'daily',
        daily_from_date,
        daily_to_date
      ).fetch_and_store_levels

      # Only update weekly levels on Sundays
      if Time.zone.today.sunday?
        weekly_from_date, weekly_to_date = calculate_weekly_dates
        Rails.logger.debug { "Weekly Levels: #{weekly_from_date} to #{weekly_to_date}" }

        LevelService.new(
          instrument.id,
          'weekly',
          weekly_from_date,
          weekly_to_date
        ).fetch_and_store_levels
      end
    end
    puts 'Levels updated!'
  end

  def calculate_daily_dates
    today = Time.zone.today
    case today.wday
    when 1, 6, 0 # Monday, Saturday, Sunday
      last_friday = today.prev_occurring(:friday)
      from_date = (last_friday - 1.day).strftime('%Y-%m-%d') # Day before Friday
      to_date = last_friday.strftime('%Y-%m-%d') # Last Friday
    else # Tuesday to Friday
      yesterday = today - 1.day
      from_date = (yesterday - 1.day).strftime('%Y-%m-%d') # Day before yesterday
      to_date = yesterday.strftime('%Y-%m-%d') # Yesterday
    end
    [from_date, to_date]
  end

  def calculate_weekly_dates
    last_week_monday = 1.week.ago.to_date.beginning_of_week.strftime('%Y-%m-%d') # Last Monday
    last_week_friday = 1.week.ago.to_date.beginning_of_week + 4.days             # Last Friday
    [last_week_monday, last_week_friday.strftime('%Y-%m-%d')]
  end
end
