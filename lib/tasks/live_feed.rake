# frozen_string_literal: true

namespace :live do
  desc 'Run the market-feed daemon (Live::MarketFeedHub). MODE=ticker|quote|full, SYMBOLS=NSE_FNO:49081,IDX_I:13'
  task feed: :environment do
    mode = (ENV['MODE'] || 'quote').to_sym
    hub = Live::MarketFeedHub.instance

    hub.start!(mode: mode)
    abort('❌ feed failed to start; check credentials and network') unless hub.running?

    subscribe_from_env(hub)
    subscribe_watchlist(hub) if ENV['SUBSCRIBE_WATCHLIST'] == 'true'
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

  desc 'Reset the simulated paper book to its starting capital'
  task paper_reset: :environment do
    account = Paper::Positions.reset!
    puts "🧹 paper book reset to ₹#{account.initial_capital.to_f.round(2)}"
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
