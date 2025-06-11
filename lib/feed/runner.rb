# frozen_string_literal: true

module Feed
  class Runner
    def self.start
      if ENV['ENABLE_FEED_LISTENER'] == 'true'
        Thread.new do
          pp '🔌 Starting FeedListener in background...'
          Dhan::Ws::FeedListener.run
        rescue StandardError => e
pp e.inspect
          Rails.logger.error("[FeedListener] ❌ #{e.class} - #{e.message}")
        end
      else
        Rails.logger.info('[Startup] FeedListener disabled via ENV')
      end

      if ENV['ENABLE_POSITION_MANAGER'] == 'true'
        Thread.new do
          pp '🧠 Starting position & order manager loop...'
          loop do
            Positions::ActiveCache.refresh!
            Positions::Manager.call
            Orders::BracketPlacer.call if ENV['ENABLE_BRACKET_PLACER'] == 'true'
            sleep 60
          end
        rescue StandardError => e
          Rails.logger.error("[ManagerLoop] ❌ #{e.class} - #{e.message}")
        end
      else
        Rails.logger.info('[Startup] Position Manager loop disabled via ENV')
      end
    end
  end
end
