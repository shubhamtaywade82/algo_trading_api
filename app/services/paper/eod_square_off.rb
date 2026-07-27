# frozen_string_literal: true

module Paper
  # Closes intraday positions near the close, the way the broker does.
  #
  # Dhan squares off open MIS/INTRADAY positions in the last minutes of the
  # session. Without this the simulated book carried them forever and marked
  # them against the next day's prices, so a paper "intraday" strategy reported
  # P&L no intraday trader could have had.
  #
  # Only INTRADAY is closed. MARGIN (NRML) and CNC are carry-forward products
  # at the broker and stay open here for the same reason.
  #
  # Idempotent per day: `last_squared_off_on` on the account means the tick
  # stream can ask on every tick without closing anything twice.
  class EodSquareOff < ApplicationService
    ZONE = 'Asia/Kolkata'
    # Matches Positions::Manager's EOD boundary, which stops managing exits at
    # the same moment for the live book.
    CUTOFF_HOUR = 15
    CUTOFF_MIN = 15
    INTRADAY_PRODUCTS = %w[INTRADAY].freeze

    class << self
      # Runs only when the session is past the cutoff and the book has not
      # already been squared off today. Safe to call on every tick.
      #
      # @return [Integer] positions closed
      def run_if_due(account: PaperAccount.current, now: Time.current.in_time_zone(ZONE))
        return 0 unless due?(now: now)

        call(account: account, now: now)
      end

      # @return [Integer] positions closed
      def call(account: PaperAccount.current, now: Time.current.in_time_zone(ZONE))
        new(account, now).call
      end

      # @return [Boolean] whether the session has reached the square-off time
      def due?(now: Time.current.in_time_zone(ZONE))
        now.on_weekday? && now >= now.change(hour: CUTOFF_HOUR, min: CUTOFF_MIN)
      end
    end

    def initialize(account = PaperAccount.current, now = Time.current.in_time_zone(ZONE))
      @account = account
      @now = now
    end

    def call
      return 0 if account.last_squared_off_on == now.to_date

      cancel_working_intraday_orders
      closed = close_intraday_positions
      account.update!(last_squared_off_on: now.to_date)
      Rails.logger.info("[Paper::EodSquareOff] squared off #{closed} intraday position(s)") if closed.positive?
      closed
    end

    private

    attr_reader :account, :now

    # A working order left alive past the close would fill against tomorrow's
    # prices on an intent formed today.
    def cancel_working_intraday_orders
      account.paper_orders.resting.where(product_type: INTRADAY_PRODUCTS).find_each do |order|
        Paper::Exchange.cancel(order.id)
      end
    end

    def close_intraday_positions
      positions = account.paper_positions.open_positions.where(product_type: INTRADAY_PRODUCTS).to_a

      positions.count do |position|
        # Braces matter: `place` takes a positional payload, so bare keywords
        # would arrive as kwargs and raise. `force` waives the market-hours
        # check — a square-off run after 15:30 still has to close the book.
        result = Paper::Exchange.place({
                                         security_id: position.security_id,
                                         exchange_segment: position.exchange_segment,
                                         transaction_type: position.net_qty.positive? ? 'SELL' : 'BUY',
                                         quantity: position.net_qty.abs,
                                         order_type: 'MARKET',
                                         product_type: position.product_type,
                                         force: true,
                                         metadata: { 'eod_square_off' => true }
                                       })
        !result[:error]
      end
    end
  end
end
