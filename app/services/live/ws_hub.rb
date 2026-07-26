# frozen_string_literal: true

module Live
  # Thin facade over {MarketFeedHub} using the `seg:`/`sid:` keyword style that
  # `Instrument#subscribe` and `Derivative#subscribe` already call with.
  #
  # Kept as a separate object rather than adding aliases to MarketFeedHub so
  # the two argument conventions stay visibly distinct at the call site: the
  # hub speaks `segment:`/`security_id:`, model callbacks speak `seg:`/`sid:`.
  class WsHub
    include Singleton

    delegate :running?, :connected?, :health, :subscriptions, to: :hub

    # @param seg [String] exchange segment, e.g. "NSE_FNO"
    # @param sid [String, Integer] security id
    def subscribe(seg:, sid:)
      hub.subscribe(segment: seg, security_id: sid)
    end

    def unsubscribe(seg:, sid:)
      hub.unsubscribe(segment: seg, security_id: sid)
    end

    def start!(mode: :quote)
      hub.start!(mode: mode)
    end

    delegate :stop!, to: :hub

    private

    def hub
      Live::MarketFeedHub.instance
    end
  end
end
