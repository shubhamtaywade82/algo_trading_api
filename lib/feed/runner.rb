# frozen_string_literal: true

module Feed
  class Runner
    def self.start
      if ENV['ENABLE_FEED_LISTENER'] == 'true'
        Thread.new do
          Rails.logger.debug '🔌 Starting FeedListener in background...'
          Positions::ActiveCache.refresh!
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
            sleep 10
          end
        rescue StandardError => e
          Rails.logger.error("[ManagerLoop] ❌ #{e.class} - #{e.message}")
        end
      else
        Rails.logger.info('[Startup] Position Manager loop disabled via ENV')
      end
    end

    def self.start_feed_listener
      Thread.new do
        while market_open?
          begin
            Dhan::Ws::FeedListener.run
          rescue StandardError => e
            log_reconnection_attempt(e)
            sleep [5, 10, 30, 60].sample # Exponential backoff
          end
        end
      end
    end

    def self.market_open?
      current_time = Time.current
      current_time.hour.between?(9, 22) ||
        (current_time.hour == 16 && current_time.min <= 10) # Allow 10min grace
    end
  end
end
