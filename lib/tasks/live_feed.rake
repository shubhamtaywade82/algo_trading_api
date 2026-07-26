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

  desc 'Show simulated paper positions and P&L'
  task paper_book: :environment do
    positions = Paper::Positions.open
    if positions.empty?
      puts 'No open paper positions.'
    else
      positions.each do |p|
        puts format('%-10s %-8s net=%-8s avg=%-10s ltp=%-10s unreal=%-10s charges=%s',
                    p[:exchange_segment], p[:security_id], p[:net_qty],
                    p[:buy_avg], p[:ltp], p[:unrealized_pnl], p[:charges])
      end
    end
    puts
    pp Paper::Positions.summary
  end

  desc 'Clear the simulated paper book (paper fills only; live orders are untouched)'
  task paper_reset: :environment do
    deleted = Paper::Positions.reset!
    puts "🧹 removed #{deleted} paper fills"
  end

  # SYMBOLS=NSE_FNO:49081,IDX_I:13
  def subscribe_from_env(hub)
    ENV['SYMBOLS'].to_s.split(',').each do |pair|
      segment, security_id = pair.strip.split(':')
      next if segment.blank? || security_id.blank?

      hub.subscribe(segment: segment, security_id: security_id)
    end
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
