# frozen_string_literal: true

module Paper
  # Rolls the simulated book onto a new trading day.
  #
  # Dhan's position book is day-scoped: yesterday's flat positions are gone,
  # yesterday's realised P&L is not today's, and a DAY order that never filled
  # is dead. The paper book is a set of database rows that survive the night, so
  # without an explicit rollover it drifted further from the broker every day —
  # stale limits waiting to fill on a week-old intent, and a daily-loss guard
  # counting losses from previous sessions.
  #
  # Lazy and idempotent: `ensure!` runs at most once per day, triggered by the
  # book's own activity, because this app has no scheduler to hang it off.
  class DayRollover < ApplicationService
    ZONE = 'Asia/Kolkata'

    class << self
      # Rolls the book if it has not been rolled today. Cheap enough to call
      # before every placement and on every tick — the common case is one date
      # comparison against an already-loaded account.
      #
      # @return [Boolean] whether a rollover ran
      def ensure!(account: PaperAccount.current, today: Time.current.in_time_zone(ZONE).to_date)
        return false if account.last_rolled_on == today

        new(account, today).call
      end
    end

    def initialize(account = PaperAccount.current, today = Time.current.in_time_zone(ZONE).to_date)
      @account = account
      @today = today
      @margin = MarginCalculator.new(account.settings)
    end

    # @return [Boolean]
    def call
      # A book that has never been rolled is simply starting its first day;
      # there is nothing from a previous session to clean up.
      if account.last_rolled_on.nil?
        account.update!(last_rolled_on: today)
        return false
      end

      expired = expire_day_orders
      dropped = drop_flat_positions
      reset_daily_realized
      account.update!(last_rolled_on: today)

      Rails.logger.info("[Paper::DayRollover] rolled onto #{today}: #{expired} order(s) expired, " \
                        "#{dropped} flat position(s) dropped")
      true
    end

    private

    attr_reader :account, :today, :margin

    # DAY validity means exactly that. Anything still resting from a previous
    # session dies with it, and its margin comes back.
    def expire_day_orders
      orders = account.paper_orders.resting.where(validity: 'DAY').to_a
      orders.each do |order|
        margin.release_order!(account, order)
        order.update!(status: 'expired', cancelled_at: Time.current)
      end
      orders.size
    end

    # The broker drops a position that closed out; keeping it would leave the
    # day-scoped position view reporting flat rows forever.
    def drop_flat_positions
      account.paper_positions.where(position_type: PaperPosition::CLOSED).delete_all
    end

    # Realised P&L on a carry-forward position belongs to the day it was
    # realised. The account keeps the cumulative figure; the position row
    # reports the current session, which is what the broker shows and what the
    # daily-loss guard has to read.
    def reset_daily_realized
      account.paper_positions.where.not(realized_profit: 0).update_all(realized_profit: 0) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
