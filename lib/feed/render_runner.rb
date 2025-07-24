# frozen_string_literal: true

#
# Render-specific background entry-points.
# - Keeps the original Feed::Runner for local/dev
# - Uses ENV flags so behaviour is symmetrical
#
module Feed
  class RenderRunner
    class << self
      # ──────────────────────────────────────────────
      # 1️⃣  Dyno that ONLY maintains the websocket
      #     (Render worker)
      # ──────────────────────────────────────────────
      def feed_only
        return Rails.logger.info('[RenderRunner] Feed disabled') unless ENV['ENABLE_FEED_LISTENER'] == 'true'

        Rails.logger.info('🔌  RenderRunner: launching FeedListener …')
        loop do
          Dhan::Ws::FeedListener.run # blocks until disconnect/error
          sleep 5
        rescue StandardError => e
          Rails.logger.error "[FeedListener] crash: #{e.class} – #{e.message}"
          sleep 5 # simple back-off
        end
      end

      # ──────────────────────────────────────────────
      # 2️⃣  One-shot manager (Render Cron)
      #     Every invocation:
      #       • refresh positions cache
      #       • run exit logic
      # ──────────────────────────────────────────────
      def run_manager_once
        return Rails.logger.info('[RenderRunner] Manager disabled') unless ENV['ENABLE_POSITION_MANAGER'] == 'true'

        Positions::ActiveCache.refresh!
        Positions::Manager.call
        Orders::BracketPlacer.call if ENV['ENABLE_BRACKET_PLACER'] == 'true'
      rescue StandardError => e
        Rails.logger.error "[RenderRunner] Manager error: #{e.class} – #{e.message}"
      end
    end
  end
end
