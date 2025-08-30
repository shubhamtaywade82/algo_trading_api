namespace :watchlists do
  desc 'Refresh a named watchlist from live candles'
  task :refresh, %i[name kind timeframe] => :environment do |_, args|
    name      = (args[:name] || 'desk_core_intraday').to_s
    kind      = (args[:kind] || 'intraday').to_s # intraday | swing | long_term
    timeframe = (args[:timeframe] || (kind == 'intraday' ? '15m' : '1d')).to_s

    Watchlists::RefreshService.call(
      name: name,
      kind: kind,
      timeframe: timeframe,
      prune: true
    )

    puts "✅ Watchlist refreshed: #{name} (#{kind}, #{timeframe})"
  end
end
