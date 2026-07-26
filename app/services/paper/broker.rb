# frozen_string_literal: true

module Paper
  # Simulated broker used when PAPER_TRADING=true.
  #
  # This is a step beyond the SDK's `config.dry_run`, which suppresses the
  # request and hands back a `DRYRUN-…` id without modelling what would have
  # happened. Here an order actually fills — at a price derived from the live
  # feed, moved against you by a slippage assumption — and the fill is
  # persisted as an `Order` row so positions and P&L can be reconstructed.
  #
  # It is reached through {Orders::Gateway}, so every caller in the app
  # (alert processors, MCP tools, Orders::Executor) gets paper behaviour
  # without knowing about it, and the result shape matches a live placement.
  #
  # What it models:
  # - fills against the current LTP (WebSocket cache first, REST fallback)
  # - slippage against the taker, scaled by order type
  # - a LIMIT order that is not marketable rests unfilled rather than filling
  #
  # What it does not model: partial fills, queue position, or depth. A large
  # order fills entirely at one price, so results flatter size more than
  # reality would.
  class Broker < ApplicationService
    # Default adverse move applied to a market fill, as a percentage.
    DEFAULT_SLIPPAGE_PCT = 0.05

    class << self
      # @param payload [Hash] the same payload a live placement would take
      # @param source [String, nil] caller identifier for logs
      # @return [Hash] gateway-shaped result
      def place(payload, source: nil)
        new(payload, source: source).place
      end

      # @return [Boolean] whether paper trading is switched on
      def enabled?
        ENV['PAPER_TRADING'] == 'true'
      end

      # @return [Float] configured slippage percentage
      def slippage_pct
        (ENV['PAPER_SLIPPAGE_PCT'] || DEFAULT_SLIPPAGE_PCT).to_f
      end
    end

    def initialize(payload, source: nil)
      @payload = payload.to_h.symbolize_keys
      @source = source
    end

    # @return [Hash] gateway-shaped result
    def place
      reference = reference_price
      return unfillable('no reference price available') unless reference&.positive?

      fill = fill_price(reference)
      return resting_order(reference) if fill.nil?

      order = record_fill!(fill)
      result_for(order, fill)
    rescue StandardError => e
      Rails.logger.error("[Paper::Broker] simulation failed#{source_suffix}: #{e.class} - #{e.message}")
      { dry_run: false, paper: true, error: true, message: e.message, payload: @payload }
    end

    private

    attr_reader :payload, :source

    def side
      @side ||= payload[:transaction_type].to_s.upcase
    end

    def buy?
      side == 'BUY'
    end

    def order_type
      @order_type ||= (payload[:order_type] || 'MARKET').to_s.upcase
    end

    def quantity
      @quantity ||= payload[:quantity].to_i
    end

    # Live mark for the instrument: the WebSocket cache when the feed is up,
    # otherwise REST. Falls back to the order's own limit price so a paper run
    # still works with no market data at all.
    def reference_price
      ws_price || rest_price || payload[:price]&.to_f
    end

    def ws_price
      Live::TickCache.ltp(payload[:exchange_segment], payload[:security_id].to_s)
    rescue StandardError
      nil
    end

    def rest_price
      instrument = Instrument.find_by(security_id: payload[:security_id].to_s)
      instrument&.ltp&.to_f
    rescue StandardError => e
      Rails.logger.debug { "[Paper::Broker] REST price lookup failed: #{e.message}" }
      nil
    end

    # @return [Float, nil] the fill price, or nil when a LIMIT order would rest
    def fill_price(reference)
      case order_type
      when 'MARKET', 'STOP_LOSS_MARKET'
        apply_slippage(reference)
      when 'LIMIT', 'STOP_LOSS'
        limit = payload[:price].to_f
        return nil unless limit.positive?
        # Marketable only when the limit is at or through the current price.
        return nil if buy? ? limit < reference : limit > reference

        # A marketable limit fills at the better of its limit and the market,
        # so it does not suffer the market-order slippage.
        buy? ? [limit, reference].min : [limit, reference].max
      else
        apply_slippage(reference)
      end
    end

    # Slippage always moves against the taker: buys fill higher, sells lower.
    def apply_slippage(reference)
      delta = reference * (self.class.slippage_pct / 100.0)
      price = buy? ? reference + delta : reference - delta
      price.positive? ? price.round(2) : reference.round(2)
    end

    def record_fill!(fill)
      Order.create!(
        dhan_order_id: paper_order_id,
        correlation_id: payload[:correlation_id],
        transaction_type: side,
        product_type: payload[:product_type].presence || 'INTRADAY',
        order_type: order_type,
        validity: payload[:validity].presence || 'DAY',
        exchange_segment: payload[:exchange_segment],
        security_id: payload[:security_id].to_s,
        quantity: quantity,
        price: payload[:price],
        trigger_price: payload[:trigger_price],
        ltp: fill,
        order_status: 'TRADED',
        filled_qty: quantity,
        average_traded_price: fill
      )
    end

    def paper_order_id
      "PAPER-#{SecureRandom.hex(6)}"
    end

    def result_for(order, fill)
      Rails.logger.info(
        "[Paper::Broker] filled #{side} #{quantity} #{payload[:security_id]} @ #{fill}#{source_suffix}"
      )
      {
        dry_run: false,
        paper: true,
        order_id: order.dhan_order_id,
        order_status: 'TRADED',
        average_traded_price: fill,
        filled_qty: quantity,
        raw: order
      }
    end

    # A non-marketable limit is a real outcome, not an error: it rests.
    def resting_order(reference)
      Rails.logger.info(
        "[Paper::Broker] #{side} #{quantity} #{payload[:security_id]} rests unfilled " \
        "(limit=#{payload[:price]}, mark=#{reference})#{source_suffix}"
      )
      {
        dry_run: false,
        paper: true,
        order_id: paper_order_id,
        order_status: 'PENDING',
        filled_qty: 0,
        message: 'Limit not marketable; order resting.',
        payload: payload
      }
    end

    def unfillable(reason)
      Rails.logger.warn("[Paper::Broker] cannot simulate fill: #{reason}#{source_suffix}")
      { dry_run: false, paper: true, error: true, message: "Paper fill not possible: #{reason}", payload: payload }
    end

    def source_suffix
      source.present? ? " (source=#{source})" : ''
    end
  end
end
