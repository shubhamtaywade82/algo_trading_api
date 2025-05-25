namespace :ws do
  desc 'Run Dhan full-feed WebSocket listener'
  task full_feed: :environment do
    puts '⚡ Starting Dhan Full Packet Feed...'
    Dhan::Ws::FeedListener.run
  end
end
