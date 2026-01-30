# frozen_string_literal: true

namespace :backtest do
  desc 'Run backtest for a strategy'
  task :run, %i[symbol from_date to_date strategy] => :environment do |_t, args|
    symbol = args[:symbol] || 'NIFTY'
    from_date = args[:from_date] || 1.month.ago.to_date.to_s
    to_date = args[:to_date] || Date.yesterday.to_s
    strategy = args[:strategy] || 'expiry_range_strategy'

    puts '🧪 Running backtest:'
    puts "   Symbol: #{symbol}"
    puts "   From: #{from_date}"
    puts "   To: #{to_date}"
    puts "   Strategy: #{strategy}"
    puts ''

    result = Backtest::Runner.call(
      symbol: symbol,
      from_date: from_date,
      to_date: to_date,
      strategy: strategy.to_sym
    )

    if result[:error]
      puts "❌ Error: #{result[:error]}"
      exit 1
    end

    puts '📊 Results:'
    puts "   Total Trades: #{result[:total_trades]}"
    puts "   Total Decisions: #{result[:total_decisions]}"

    if result[:decisions_summary]
      summary = result[:decisions_summary]
      puts "   Decisions: BUY=#{summary[:buy]}, WAIT=#{summary[:wait]}, NO_TRADE=#{summary[:no_trade]}"
    end

    if result[:metrics]&.any?
      puts '   Metrics:'
      result[:metrics].each do |key, value|
        puts "      #{key}: #{value}"
      end
    end

    puts ''
    puts '📈 Trades:'
    if result[:trades].any?
      result[:trades].each_with_index do |trade, idx|
        puts "   #{idx + 1}. #{trade[:entry_date]} - #{trade[:option_type]} #{trade[:strike]} @ ₹#{trade[:entry_premium]}"
        puts "      Entry Spot: ₹#{trade[:entry_spot]}"
        puts "      SL: ₹#{trade[:stop_loss]} | Target: ₹#{trade[:target]}"
      end
    else
      puts '   No trades generated'
    end

    puts ''
    puts '✅ Backtest completed!'
  end

  desc 'Backtest expiry range strategy for last N days'
  task :expiry_range, %i[symbol days] => :environment do |_t, args|
    symbol = args[:symbol] || 'NIFTY'
    days = (args[:days] || 30).to_i

    to_date = MarketCalendar.last_trading_day
    from_date = MarketCalendar.last_trading_day(from: to_date - days.days)

    Rake::Task['backtest:run'].invoke(symbol, from_date.to_s, to_date.to_s, 'expiry_range_strategy')
  end

  desc 'Backtest options buying strategy for last N days'
  task :options_buying, %i[symbol days] => :environment do |_t, args|
    symbol = args[:symbol] || 'NIFTY'
    days = (args[:days] || 30).to_i

    to_date = MarketCalendar.last_trading_day
    from_date = MarketCalendar.last_trading_day(from: to_date - days.days)

    Rake::Task['backtest:run'].invoke(symbol, from_date.to_s, to_date.to_s, 'options_buying')
  end
end
