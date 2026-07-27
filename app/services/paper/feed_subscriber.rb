# frozen_string_literal: true

module Paper
  # Keeps the market feed watching whatever the simulated book is trading.
  #
  # The feed is the matching engine's clock: {Paper::Exchange} fills resting
  # orders, marks positions and triggers super-order legs from ticks, and
  # nothing else subscribes what a strategy picks at signal time — an option
  # strike is not known until the alert arrives. An unsubscribed instrument
  # rests forever and its position never marks.
  #
  # Every method here is additive and none of them start the feed, so a process
  # running without one is unaffected and keeps falling back to REST pricing.
  class FeedSubscriber
    class << self
      # @param segment [String] e.g. "NSE_FNO"
      # @param security_id [String, Integer]
      # @return [Boolean] whether the feed is now watching this instrument
      def follow(segment:, security_id:)
        hub = Live::MarketFeedHub.instance
        return false unless hub.running?

        hub.subscribe(segment: segment, security_id: security_id)
      rescue StandardError => e
        Rails.logger.warn("[Paper::FeedSubscriber] could not subscribe #{segment}:#{security_id}: #{e.message}")
        false
      end

      # Puts the feed back on everything the book still has working, after a
      # restart or a fresh `live:feed`. Without it, orders and positions that
      # survived in the database go unticked: nothing fills, nothing marks.
      #
      # @param account [PaperAccount]
      # @return [Integer] instruments subscribed
      def restore_book!(account: PaperAccount.current)
        instruments = account.paper_orders.resting.pluck(:exchange_segment, :security_id) +
                      account.paper_positions.open_positions.pluck(:exchange_segment, :security_id)

        instruments.uniq.count { |segment, security_id| follow(segment: segment, security_id: security_id) }
      end
    end
  end
end
