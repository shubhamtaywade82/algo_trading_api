# frozen_string_literal: true

require 'csv'

namespace :levels do
  desc 'Update daily and weekly levels for instruments in instraday_stocks.csv'
  task update: :environment do
    # Load symbols from CSV
    file_path = Rails.root.join('db/seeds/intraday_stocks.csv')
    stocks = CSV.read(file_path, headers: true).pluck('SYMBOL_NAME')

    Rails.logger.debug { "Loaded #{stocks.size} symbols from CSV." }
    # Fetch instruments in bulk
    instruments = Instrument.where(underlying_symbol: stocks)
    instruments.pluck(:underlying_symbol)

    instruments.each do |instrument|
      Rails.logger.debug { "Processing instrument: #{instrument.symbol_name}" }

      # Calculate dates for daily levels
      daily_from_date, daily_to_date = calculate_daily_dates
      Rails.logger.debug { "Daily Levels: From #{daily_from_date} To #{daily_to_date}" }

      LevelService.new(instrument.id, 'daily', daily_from_date, daily_to_date).fetch_and_store_levels

      # Only update weekly levels on Sundays
      if Time.zone.today.sunday? || Time.zone.today.saturday?
        weekly_from_date, weekly_to_date = calculate_weekly_dates
        Rails.logger.debug { "Weekly Levels: #{weekly_from_date} to #{weekly_to_date}" }

        LevelService.new(instrument.id, 'weekly', weekly_from_date, weekly_to_date).fetch_and_store_levels
      end

      # Delay next iteration by 5 seconds
      sleep(5)
    end

    # Log missing symbols
    if missing_symbols.any?
      Rails.logger.error { "Symbols not found: #{missing_symbols.join(', ')}" }
      puts "Symbols not found: #{missing_symbols.join(', ')}"
    else
      puts 'All symbols processed successfully.'
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
