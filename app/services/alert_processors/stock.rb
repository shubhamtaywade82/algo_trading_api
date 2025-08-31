# frozen_string_literal: true

module AlertProcessors
  # Refactored STOCK processor – mirrors the flow & logging style of the
  # Index processor (metadata logging, skip! helper, tagged logs, etc.)
  # ----------------------------------------------------------------------------
  class Stock < Base
    include Strategies

    STRATEGY = {
      'intraday' => Strategies::Intraday,
      'swing' => Strategies::Swing,
      'long_term' => Strategies::LongTerm
    }.freeze

    PRODUCT = {
      'intraday' => Dhanhq::Constants::INTRA,
      'swing' => Dhanhq::Constants::CNC,
      'long_term' => Dhanhq::Constants::CNC
    }.freeze

    LONG_ONLY      = %w[swing long_term].freeze
    LONG_SIGNALS   = %w[long_entry long_exit].freeze
    SHORT_SIGNALS  = %w[short_entry short_exit].freeze

    # sizing constants --------------------------------------------------------
    RISK_PER_TRADE     = 0.02  # 2 % of equity
    FUNDS_UTILIZATION  = 0.30  # 30 % of free cash per trade

    EDIS_POLL_INTERVAL = 5.seconds
    EDIS_TIMEOUT       = 45.seconds

    # ------------------------------------------------------------------------
    #  Entry‑point (called from controller / worker)
    # ------------------------------------------------------------------------
    def call
      with_tag do
        return skip! unless signal_guard?

        order = build_order_payload
        ENV['PLACE_ORDER'] == 'true' ? place_order!(order) : dry_run(order)

        alert.update!(status: :processed)
      end
    rescue StandardError => e
      alert.update!(status: :failed, error_message: e.message)
      logger.error("[Stock ##{alert.id}] #{e.class} – #{e.message}\n" \
                   "#{e.backtrace.first(6).join("\n")}")
    end

    # ------------------------------------------------------------------------
    #  Strategy descriptor
    # ------------------------------------------------------------------------
    def strat
      @strat ||= STRATEGY.fetch(alert[:strategy_type]).new(self)
    end

    # ------------------------------------------------------------------------
    #  Guards / validation
    # ------------------------------------------------------------------------
    def signal_guard?
      return skip!(:short_not_allowed) if LONG_ONLY.include?(alert[:strategy_type]) && SHORT_SIGNALS.include?(alert[:signal_type])

      case alert[:signal_type]
      when 'long_entry'  then return skip!(:already_long)   if current_qty.positive?
      when 'long_exit'   then return skip!(:no_long)        if current_qty.zero?
      when 'short_entry' then return skip!(:already_short)  if current_qty.negative?
      when 'short_exit'  then return skip!(:no_short)       if current_qty.zero?
      end
      true
    end

    # --------------------------------------------------------------------
    #  Order building – honours DhanHQ field-matrix
    # --------------------------------------------------------------------
    def build_order_payload
      order_type  = alert[:order_type].to_s.upcase
      txn_side    = side_for(alert[:signal_type])

      payload = {
        transactionType: txn_side,
        orderType: order_type, # MARKET / LIMIT / SL / SLM
        productType: PRODUCT.fetch(alert[:strategy_type]),
        validity: Dhanhq::Constants::DAY,
        exchangeSegment: instrument.exchange_segment,
        securityId: instrument.security_id,
        quantity: calculate_quantity!
      }

      # Set price based on order type
      if order_type == 'STOP_LOSS_MARKET'
        trigger = derived_stop_price(txn_side)
        payload[:triggerPrice] = PriceMath.round_tick(trigger)
        payload[:price]        = 0 # Market order
      elsif order_type == 'STOP_LOSS'
        trigger = derived_stop_price(txn_side)
        payload[:triggerPrice] = PriceMath.round_tick(trigger)
        payload[:price]        = PriceMath.round_tick(ltp)
      else
        payload[:price] = PriceMath.round_tick(ltp)
      end

      payload
    end

    def side_for(sig)
      case sig
      when 'long_entry',  'short_exit'  then 'BUY'
      when 'long_exit',   'short_entry' then 'SELL'
      else raise "Unknown signal_type #{sig}"
      end
    end

    # ------------------------------------------------------------------------
    #  Sizing helpers
    # ------------------------------------------------------------------------
    def calculate_quantity!
      return current_qty.abs if closing_trade?

      risk_qty = (available_balance * RISK_PER_TRADE / ltp).floor
      cash_cap = (available_balance * FUNDS_UTILIZATION * leverage_factor / ltp).floor
      qty      = [risk_qty, cash_cap].min
      qty      = [qty, min_lot_by_price].max
      raise 'buying‑power insufficient for minimum lot' if qty.zero?

      qty
    end

    def closing_trade?
      (alert[:signal_type] == 'long_exit' && current_qty.positive?) ||
        (alert[:signal_type] == 'short_exit' && current_qty.negative?)
    end

    # min‑lot table (mirrors Dhan UI) ----------------------------------------
    def min_lot_by_price
      base = case ltp
             when 0..50       then 250
             when 51..200     then 50
             when 201..500    then 25
             when 501..1_000  then 5
             else 1
             end
      PRODUCT.fetch(alert[:strategy_type]) == Dhanhq::Constants::INTRA ? base * 2 : base
    end

    # ------------------------------------------------------------------------
    #  Execution helpers
    # ------------------------------------------------------------------------
    def place_order!(payload)
      resp = Dhanhq::API::Orders.place(payload) # => {'orderId'=>…}
      ensure_edis!(payload[:quantity]) if cnc_sell?(payload)
      alert.update!(metadata: { placed_order: resp })
      logger.info("[Stock ##{alert.id}] ✅ placed #{resp}")
    end

    def dry_run(payload)
      alert.update!(status: :skipped,
                    error_message: 'PLACE_ORDER disabled',
                    metadata: { simulated_order: payload })
      logger.info("[Stock ##{alert.id}] 💡 dry‑run #{payload}")
    end

    def cnc_sell?(payload)
      payload[:productType] == Dhanhq::Constants::CNC &&
        payload[:transactionType] == 'SELL'
    end

    # eDIS (idempotent)
    def ensure_edis!(qty)
      info = Dhanhq::API::EDIS.status(isin: instrument.isin)
      return if info['status'] == 'SUCCESS' && info['aprvdQty'].to_i >= qty

      Dhanhq::API::EDIS.mark(
        isin: instrument.isin,
        qty: qty,
        exchange: instrument.exchange.upcase,
        segment: 'EQ',
        bulk: true
      )

      start = Time.current
      loop do
        sleep EDIS_POLL_INTERVAL
        info = Dhanhq::API::EDIS.status(isin: instrument.isin)
        break if info['status'] == 'SUCCESS' && info['aprvdQty'].to_i >= qty
        raise 'eDIS approval timed‑out' if Time.current - start > EDIS_TIMEOUT
      end
    end

    # ------------------------------------------------------------------------
    #  Helpers delegated to Base / external
    # ------------------------------------------------------------------------
    def current_qty
      pos = dhan_positions.find { |p| p['securityId'].to_s == instrument.security_id.to_s }
      pos&.dig('netQty').to_i
    end
    alias fetch_current_net_quantity current_qty

    def leverage_factor
      lev = instrument.mis_detail&.mis_leverage.to_i
      lev.positive? ? lev : 1.0
    end

    # ------------------------------------------------------------------------
    #  Logging helpers
    # ------------------------------------------------------------------------
    def with_tag(&)
      logger.tagged("Stock ##{alert.id}", &)
    end

    def skip!(reason = nil)
      reason ? alert.update!(status: :skipped, error_message: reason.to_s) : alert.update!(status: :skipped)
      logger.info("[Stock ##{alert.id}] skip – #{reason}")
      false
    end

    def logger = Rails.logger

    def derived_stop_price(txn_side)
      base_trigger = stop_price_from_metadata
      return base_trigger if base_trigger.positive?

      margin = PriceMath.round_tick(ltp * 0.05)
      case txn_side
      when 'BUY'  then (ltp - margin)   # long stop 5 % below entry
      when 'SELL' then (ltp + margin)   # short stop 5 % above entry
      else
        raise "Unexpected txn_side #{txn_side}"
      end
    end
    private :derived_stop_price

    # Reads a numeric :stop_price inside alert.metadata (if present)
    # Returns 0.0 when the key is missing or not numeric.
    def stop_price_from_metadata
      m = alert.metadata || {}
      price = m['stop_price'] || m[:stop_price]
      price.to_f
    rescue StandardError
      0.0
    end
  end
end
