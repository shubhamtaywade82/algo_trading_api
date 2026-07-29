# frozen_string_literal: true

namespace :live do
  desc 'Run the market-feed daemon (Live::MarketFeedHub). MODE=ticker|quote|full, SYMBOLS=NSE_FNO:49081,IDX_I:13'
  task feed: :environment do
    unbuffer_stdout!
    mode = (ENV['MODE'] || 'quote').to_sym
    hub = Live::MarketFeedHub.instance

    hub.start!(mode: mode)
    abort('❌ feed failed to start; check credentials and network') unless hub.running?

    subscribe_from_env(hub)
    subscribe_watchlist(hub) if ENV['SUBSCRIBE_WATCHLIST'] == 'true'
    subscribe_index_watchlist(hub) if ENV['SUBSCRIBE_INDEX_WATCHLIST'] == 'true'
    subscribe_paper_book if Paper::Broker.enabled?

    puts "⚡ market feed running (mode=#{mode}, subscriptions=#{hub.subscriptions.size})"
    puts '   Ctrl-C to stop.'

    trap('INT') do
      puts "\n… stopping feed"
      hub.stop!
      exit 0
    end

    # The SDK runs its own reader thread; this loop only reports health.
    loop do
      sleep 30
      health = hub.health
      puts "[feed] connected=#{health[:connected]} ticks=#{health[:cached_ticks]} " \
           "subs=#{health[:tracked_subscriptions]} reconnects=#{health[:reconnect_count]}"
    end
  end

  desc 'Print a one-shot health snapshot of the market feed'
  task feed_health: :environment do
    pp Live::MarketFeedHub.instance.health
  end

  desc 'Show simulated paper positions, working orders and P&L'
  task paper_book: :environment do
    positions = Paper::Positions.open
    if positions.empty?
      puts 'No open paper positions.'
    else
      positions.each do |p|
        puts format('%<segment>-10s %<security_id>-8s %<position_type>-7s net=%<net_qty>-7s ' \
                    'avg=%<buy_avg>-10s ltp=%<ltp>-10s unreal=%<unrealized>-10s real=%<realized>s',
                    segment: p[:exchange_segment], security_id: p[:security_id],
                    position_type: p[:position_type], net_qty: p[:net_qty], buy_avg: p[:buy_avg],
                    ltp: p[:ltp], unrealized: p[:unrealized_pnl], realized: p[:realized_pnl])
      end
    end

    working = Paper::Positions.open_orders
    if working.any?
      puts "\nWorking orders:"
      working.each do |o|
        puts format('  #%<id>-6s %<side>-4s %<order_type>-18s qty=%<quantity>-6s ' \
                    'filled=%<filled_qty>-6s px=%<price>-10s status=%<status>s',
                    id: o[:id], side: o[:side], order_type: o[:order_type], quantity: o[:quantity],
                    filled_qty: o[:filled_qty], price: o[:price], status: o[:status])
      end
    end

    puts
    pp Paper::Positions.summary
  end

  desc 'Square off the paper book\'s intraday positions now (as the broker would at 15:15 IST)'
  task paper_eod: :environment do
    closed = Paper::EodSquareOff.call
    puts "🔔 squared off #{closed} intraday paper position(s)"
    pp Paper::Positions.summary
  end

  desc 'Roll the paper book onto the current trading day (expire DAY orders, drop flat positions)'
  task paper_roll: :environment do
    if Paper::DayRollover.ensure!
      puts '📆 paper book rolled onto the current session'
    else
      puts '📆 paper book was already on the current session'
    end
  end

  desc 'Reset the simulated paper book to its starting capital'
  task paper_reset: :environment do
    account = Paper::Positions.reset!
    puts "🧹 paper book reset to ₹#{account.initial_capital.to_f.round(2)}"
  end

  desc 'Set the paper book\'s capital (CAPITAL=100000, or PAPER_CAPITAL) and reset it to that figure'
  task paper_capital: :environment do
    amount = ENV['CAPITAL'].presence || ENV.fetch('PAPER_CAPITAL', nil)
    account = PaperAccount.recapitalize!(amount)
    puts "💰 paper book re-capitalised to ₹#{account.initial_capital.to_f.round(2)} (positions and orders cleared)"
    pp Paper::Positions.summary
  end

  desc 'Run the paper-trading engine: market feed + index watchlist scanner in one process'
  task paper_engine: :environment do
    unbuffer_stdout!
    guard_paper_engine!

    hub = Live::MarketFeedHub.instance
    start_token_refresher

    hub.start!(mode: (ENV['MODE'] || 'quote').to_sym)
    abort('❌ feed failed to start; check credentials and network') unless hub.running?

    subscribe_index_watchlist(hub)
    subscribe_paper_book

    puts "📄 paper engine up — book ₹#{PaperAccount.current.initial_capital.to_f.round(2)}, " \
         "watching #{Market::IndexWatchlist.symbols.join(', ')}"
    puts "   trading=#{Market::IndexWatchlist.trading_enabled?} " \
         "min_level=#{Market::IndexWatchlist.min_level} " \
         "scan=#{Market::IndexWatchlist.scan_interval}s " \
         "cap=#{Market::IndexWatchlist.max_trades_per_day}/symbol/day"

    trap('INT') do
      puts "\n… stopping paper engine"
      hub.stop!
      exit 0
    end

    run_paper_engine_loop(hub)
  end

  # Ruby leaves $stdout block-buffered whenever it is not a TTY — a pipe to a
  # log collector, a supervisor, a shell redirect. The buffer only flushes at
  # 8 KB or on exit, and these tasks are daemons that do neither for a whole
  # session, so their output is invisible for hours while the process is
  # perfectly healthy. `bin/ws_feed` has set this since it was written; these
  # tasks are the same kind of process and need the same line.
  #
  # config/environments/production.rb sets this too, so the deployed worker is
  # covered before the task body runs. It is repeated here because the trap is
  # a property of the *process shape*, not the environment: the same daemon run
  # in development under a supervisor buffers identically.
  def unbuffer_stdout!
    $stdout.sync = true
  end

  # The engine places orders on its own initiative, so it refuses to run
  # anywhere they could reach a broker. PAPER_ENGINE_ALLOW_LIVE is the
  # deliberate override, and it is not set anywhere in this repo.
  def guard_paper_engine!
    return if Paper::Broker.enabled?

    if ENV['PAPER_ENGINE_ALLOW_LIVE'] == 'true'
      warn('⚠️  paper engine running with PAPER_TRADING off — orders will take the live path')
      return
    end

    abort('❌ refusing to run: PAPER_TRADING is not enabled. Set PAPER_TRADING=true, ' \
          'or PAPER_ENGINE_ALLOW_LIVE=true to run this against the live path on purpose.')
  end

  # config/initializers/dhan_token_bootstrap.rb and dhan_token_scheduler.rb both
  # skip when Rake is defined, so that a db:migrate never reaches auth.dhan.co.
  # A long-lived rake process still needs both, so it does them itself.
  def start_token_refresher
    Dhan::TokenManager.current_token!
    Thread.new do
      loop do
        sleep 5.minutes
        Dhan::TokenManager.current_token!
      rescue StandardError => e
        Rails.logger.error("[paper_engine] token refresh failed: #{e.class}: #{e.message}")
      end
    end
  rescue StandardError => e
    abort("❌ could not mint a Dhan access token: #{e.class}: #{e.message}")
  end

  # One process holds the feed *and* runs the scan because Live::TickCache is
  # process-local: a scanner in another process would place orders that no tick
  # stream ever fills or marks.
  def run_paper_engine_loop(hub)
    loop do
      scan_index_watchlist if paper_engine_session?
      report_paper_engine_health(hub)
      sleep Market::IndexWatchlist.scan_interval
    end
  end

  def scan_index_watchlist
    Market::AnalysisUpdater.call
  rescue StandardError => e
    Rails.logger.error("[paper_engine] scan failed: #{e.class}: #{e.message}")
  end

  # 09:15–15:30 IST, weekdays, excluding market holidays. Outside it the REST
  # calls the scan makes would return the same stale candles every cycle. The
  # feed itself stays up — a reconnect out of hours is cheaper than a cold
  # start at 09:15.
  def paper_engine_session?
    MarketCalendar.market_open?
  end

  def report_paper_engine_health(hub)
    health = hub.health
    summary = Paper::Positions.summary
    puts "[engine] connected=#{health[:connected]} ticks=#{health[:cached_ticks]} " \
         "subs=#{health[:tracked_subscriptions]} open=#{summary[:open_positions]} " \
         "net_pnl=#{summary[:net_pnl]} capital=#{summary[:current_capital]}"
  rescue StandardError => e
    Rails.logger.warn("[paper_engine] health snapshot failed: #{e.message}")
  end

  # SYMBOLS=NSE_FNO:49081,IDX_I:13
  def subscribe_from_env(hub)
    ENV['SYMBOLS'].to_s.split(',').each do |pair|
      segment, security_id = pair.strip.split(':')
      next if segment.blank? || security_id.blank?

      hub.subscribe(segment: segment, security_id: security_id)
    end
  end

  # Anything the paper book still has working needs ticks from the moment the
  # feed comes up, not from the next order.
  def subscribe_paper_book
    count = Paper::FeedSubscriber.restore_book!
    puts "📄 paper book restored: #{count} instrument(s) subscribed"
  rescue StandardError => e
    Rails.logger.warn("[live:feed] could not restore paper-book subscriptions: #{e.message}")
  end

  # The spot index itself, so the scanner's marks and the option leg's
  # underlying both tick. Strikes are subscribed by Paper::FeedSubscriber as
  # they are traded — nobody knows which strike until the signal fires.
  def subscribe_index_watchlist(hub)
    subscribed = Market::IndexWatchlist.instruments.count do |instrument|
      hub.subscribe(segment: instrument.exchange_segment, security_id: instrument.security_id)
    end
    puts "📈 index watchlist: #{subscribed} of #{Market::IndexWatchlist.symbols.size} subscribed"
    subscribed
  end

  def subscribe_watchlist(hub)
    WatchlistItem.where(active: true).includes(:watchable).find_each do |item|
      watchable = item.watchable
      next unless watchable.respond_to?(:exchange_segment)

      hub.subscribe(segment: watchable.exchange_segment, security_id: watchable.security_id)
    rescue StandardError => e
      Rails.logger.warn("[live:feed] could not subscribe watchlist item #{item.id}: #{e.message}")
    end
  end
end
