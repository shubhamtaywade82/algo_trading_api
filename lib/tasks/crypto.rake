# frozen_string_literal: true

namespace :crypto do
  desc 'Scan the configured pairs for SMC/ICT setups and alert on Telegram. SYMBOLS=SOLUSDT,ETHUSDT'
  task scan: :environment do
    symbols = ENV['SYMBOLS'].to_s.split(',').map { |s| s.strip.upcase }.reject(&:empty?)
    results = Crypto::Scanner.call(symbols: symbols.presence)

    if results.empty?
      puts "No qualifying setups (#{(symbols.presence || Crypto::Config.symbols).join(', ')})."
      next
    end

    results.each do |result|
      setup = result.setup
      puts "#{setup.symbol} #{setup.side} · grade #{setup.grade} · score #{setup.score} · " \
           "R:R #{setup.risk_reward} · telegram=#{result.status}"
    end
  end

  desc 'Print the multi-timeframe SMC read for one pair without alerting. SYMBOL=SOLUSDT'
  task report: :environment do
    symbol = (ENV['SYMBOL'].presence || Crypto::Config.symbols.first).upcase
    analyzer = Crypto::Analyzer.new(symbol)
    reports = analyzer.reports

    abort("❌ Could not fetch market data for #{symbol}") if reports.nil?

    puts "── #{symbol} ─────────────────────────────"
    Crypto::Config::TIMEFRAMES.each do |timeframe|
      report = reports[timeframe]
      summary = report.summary
      puts format('%-4<tf>s bias=%-8<bias>s price=%-12<price>s zone=%-12<zone>s last=%<event>s',
                  tf: timeframe,
                  bias: summary[:bias],
                  price: Crypto::Formatting.price(summary[:price]),
                  zone: summary[:zone] || 'n/a',
                  event: summary[:last_event] || 'none')
    end

    setup = Crypto::SetupDetector.call(symbol: symbol, reports: reports)
    puts
    if setup
      puts Crypto::SetupFormatter.call(setup)
    else
      puts "No qualifying setup — needs a 5m trigger, score >= #{Crypto::Config.min_score} " \
           "and R:R >= #{Crypto::Config.min_risk_reward}."
    end
  end

  desc 'Run the event-driven kline stream: scans the moment a candle closes'
  task stream: :environment do
    abort('❌ CRYPTO_SMC_ENABLED is not true — refusing to start the stream.') unless Crypto::Config.enabled?

    stream = Crypto::Binance::KlineStream.new
    puts "⚡ streaming #{stream.symbols.join(', ')} on #{stream.timeframes.join(', ')} — Ctrl-C to stop."

    trap('INT') do
      puts "\n… stopping stream"
      EM.stop if EM.reactor_running?
      exit 0
    end

    stream.run
  end

  desc 'Show the resolved scanner configuration'
  task config: :environment do
    puts "enabled:        #{Crypto::Config.enabled?}"
    puts "symbols:        #{Crypto::Config.symbols.join(', ')}"
    puts "timeframes:     #{Crypto::Config::TIMEFRAMES.join(', ')} (execution: #{Crypto::Config::EXECUTION_TIMEFRAME})"
    puts "stream on:      #{Crypto::Config.stream_timeframes.join(', ')}"
    puts "min score:      #{Crypto::Config.min_score}"
    puts "min R:R:        #{Crypto::Config.min_risk_reward}"
    puts "cooldown:       #{(Crypto::Config.cooldown_seconds / 60).round} min"
    puts "telegram chat:  #{Crypto::Config.telegram_chat_id.presence || '(unset)'}"
  end
end
