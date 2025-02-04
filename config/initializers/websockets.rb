# # frozen_string_literal: true

# Thread.new do
#   # Start Live Market Feed WebSocket
#   begin
#     market_feed = LiveMarketFeed.new
#     market_feed.connect
#   rescue StandardError => e
#     Rails.logger.error "[WebSocket] Error starting LiveMarketFeed: #{e.message}"
#   end

#   # Start Live Order Update WebSocket
#   begin
#     order_update = LiveOrderUpdate.new
#     order_update.connect
#   rescue StandardError => e
#     Rails.logger.error "[WebSocket] Error starting LiveOrderUpdate: #{e.message}"
#   end
# end
