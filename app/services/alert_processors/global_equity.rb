# frozen_string_literal: true

module AlertProcessors
  # Processes TradingView alerts for US equities on DhanHQ's Global Stocks book.
  #
  # This book differs from the domestic one in ways that shape the whole flow:
  #
  # - **No scrip master.** US tickers are not in the `instruments` table, so
  #   `Base#instrument` cannot resolve them. The alert's ticker *is* the
  #   `security_id` ("AAPL"), and nothing here touches `Instrument`.
  # - **USD.** Sizing reads `GlobalStocks::Funds.available_cash`, not the
  #   domestic fund limit. The two must never be mixed.
  # - **Fractional shares.** Quantities are Floats, and an `AMOUNT` order buys a
  #   notional USD value instead of a share count.
  # - **US market hours.** `MarketCalendar` covers NSE/BSE, so the open check
  #   goes through `GlobalStocks::MarketStatus`.
  # - **No risk pipeline.** The SDK deliberately skips `Risk::Pipeline` here
  #   because its checks resolve instruments from the Indian scrip master, so
  #   the exposure guards below are this book's only pre-trade limits.
  #
  # Placement still goes through `Orders::Gateway`, so `PLACE_ORDER` and
  # `LIVE_TRADING` gate US orders exactly as they gate domestic ones.
  class GlobalEquity < Base
    # Fraction of available USD cash a single position may consume.
    ALLOCATION_PCT = (ENV['GLOBAL_ALLOC_PCT'] || 20).to_f
    # Refuse to size a position below this notional; below it the trade is noise.
    MIN_NOTIONAL_USD = 5.0

    ENTRY_SIGNALS = %w[long_entry].freeze
    EXIT_SIGNALS = %w[long_exit short_entry].freeze

    def call
      with_tag do
        return skip!(:market_closed) unless market_open?
        return skip!(:unsupported_signal) unless supported_signal?

        payload = build_order_payload
        return skip!(:insufficient_funds) if payload.nil?

        place_order!(payload)
        alert.update!(status: :processed)
      end
    rescue StandardError => e
      alert.update!(status: :failed, error_message: e.message)
      logger.error("[GlobalEquity ##{alert.id}] #{e.class} – #{e.message}\n#{e.backtrace.first(6).join("\n")}")
    end

    # US ticker, taken straight from the alert. Deliberately not an Instrument.
    # @return [String]
    def security_id
      @security_id ||= alert[:ticker].to_s.strip.upcase
    end

    # @return [Float] last traded price in USD, 0.0 when unavailable
    def ltp
      @ltp ||= alert[:current_price].to_f
    end

    private

    def market_open?
      DhanHQ::Models::GlobalStocks::MarketStatus.open?
    rescue StandardError => e
      # Fail closed: an unknown market state must not authorise a trade.
      logger.warn("[GlobalEquity ##{alert.id}] market status unavailable (#{e.message}); treating as closed")
      false
    end

    def supported_signal?
      (ENTRY_SIGNALS + EXIT_SIGNALS).include?(alert[:signal_type].to_s)
    end

    def entry?
      ENTRY_SIGNALS.include?(alert[:signal_type].to_s)
    end

    # @return [Hash, nil] gateway payload, or nil when the trade cannot be sized
    def build_order_payload
      entry? ? entry_payload : exit_payload
    end

    def entry_payload
      quantity = entry_quantity
      return nil unless quantity.positive?

      base_payload('BUY').merge(quantity: quantity)
    end

    # Exits close the whole position; there is nothing to size.
    def exit_payload
      held = held_quantity
      return nil unless held.positive?

      base_payload('SELL').merge(quantity: held)
    end

    def base_payload(side)
      payload = {
        security_id: security_id,
        transaction_type: side,
        order_type: order_type,
        correlation_id: "GE-#{alert.id}"
      }
      payload[:price] = ltp if order_type == 'LIMIT'
      payload
    end

    # A LIMIT order needs a price; without one from the alert, cross at market.
    def order_type
      ltp.positive? ? 'LIMIT' : 'MARKET'
    end

    # Fractional shares are supported, so this is a Float rather than a lot count.
    # @return [Float]
    def entry_quantity
      return 0.0 unless ltp.positive?

      budget = available_cash * (ALLOCATION_PCT / 100.0)
      return 0.0 if budget < MIN_NOTIONAL_USD

      (budget / ltp).round(4)
    end

    # @return [Float] shares currently held of this ticker
    def held_quantity
      holding = DhanHQ::Models::GlobalStocks::Holding.all.find do |h|
        h.security_id.to_s.casecmp?(security_id) || h.trading_symbol.to_s.casecmp?(security_id)
      end
      # GlobalStocks::Holding exposes `quantity`; `total_qty` is the domestic
      # Holding's attribute and is not defined here.
      holding ? holding.quantity.to_f : 0.0
    rescue StandardError => e
      logger.warn("[GlobalEquity ##{alert.id}] holdings fetch failed: #{e.message}")
      0.0
    end

    # USD buying power. Never falls back to the domestic balance.
    # @return [Float]
    def available_cash
      @available_cash ||= DhanHQ::Models::GlobalStocks::Funds.balance.to_f
    rescue StandardError
      raise 'Failed to fetch Global Stocks available cash'
    end

    def place_order!(payload)
      result = Orders::Gateway.place_global_order(payload, source: self.class.name)

      if result[:dry_run] || result[:blocked]
        logger.info("[GlobalEquity ##{alert.id}] dry-run – #{result[:message]}")
        return result
      end

      if result[:error]
        # A reconcilable error means the order may already be live; never resend.
        raise "Global order failed (#{result[:reconcilable] ? 'reconcile by correlation_id' : 'rejected'}): #{result[:message]}"
      end

      notify_placement(payload, result)
      result
    end

    def notify_placement(payload, result)
      notify(
        "🇺🇸 US #{payload[:transaction_type]} #{payload[:quantity]} #{security_id} " \
        "@ $#{payload[:price] || 'MKT'} | order #{result[:order_id]}"
      )
    rescue StandardError => e
      logger.warn("[GlobalEquity ##{alert.id}] notify failed: #{e.message}")
    end

    def with_tag(&)
      logger.tagged("GlobalEquity ##{alert.id}", &)
    end

    def skip!(reason = nil)
      reason ? alert.update!(status: :skipped, error_message: reason.to_s) : alert.update!(status: :skipped)
      logger.info("[GlobalEquity ##{alert.id}] skip – #{reason}")
      false
    end

    def logger = Rails.logger
  end
end
