# frozen_string_literal: true

module Positions
  # The open-position book for whichever destination this process trades.
  #
  # The exit stack — ActiveCache, Positions::Manager, Orders::Manager — was
  # written against DhanHQ::Models::Position directly, so during a paper run it
  # inspected an empty live account and no simulated position was ever managed:
  # no trailing stop, no risk exit, nothing. Reading through here means the same
  # exit rules run against whichever book the orders actually went to, and the
  # exits they place route back to Paper::Exchange through Orders::Gateway.
  class Source
    class << self
      # @return [Array<Hash>] positions in the broker's attribute shape
      def all
        return Paper::Positions.dhan_shaped if Paper::Broker.enabled?

        DhanHQ::Models::Position.all.map(&:attributes)
      end

      # @return [Array<Hash>] positions carrying a non-zero net quantity
      def open
        all.reject { |position| (position['netQty'] || position[:net_qty]).to_f.zero? }
      end
    end
  end
end
