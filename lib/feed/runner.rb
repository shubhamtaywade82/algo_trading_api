# frozen_string_literal: true

module Feed
  class Runner
    def self.start
      if ENV['ENABLE_FEED_LISTENER'] == 'true'
        Thread.new do
          Rails.logger.debug '🔌 Starting FeedListener in background...'
          Dhan::Ws::FeedListener.run
        rescue StandardError => e
          Rails.logger.error("[FeedListener] ❌ #{e.class} - #{e.message}")
        end
      else
        Rails.logger.info('[Startup] FeedListener disabled via ENV')
      end

      if ENV['ENABLE_POSITION_MANAGER'] == 'true'
        Thread.new do
          Rails.logger.debug '🧠 Starting position & order manager loop...'
          loop do
            Positions::ActiveCache.refresh!
            Positions::Manager.call
            Orders::BracketPlacer.call if ENV['ENABLE_BRACKET_PLACER'] == 'true'
            sleep 30
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
