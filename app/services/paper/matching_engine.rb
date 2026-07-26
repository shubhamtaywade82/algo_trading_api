# frozen_string_literal: true

module Paper
  # Decides *what price* a simulated order fills at and *how much* of it fills.
  #
  # Three slippage models, chosen per account via `config[:slippage_model]`:
  #
  # - `fixed_bps` — a flat basis-point haircut. Cheap and predictable.
  # - `spread_based` — half the live bid/ask spread, taken from the depth the
  #   WebSocket feed caches. The most honest model when depth is available,
  #   since crossing the spread is the cost you actually pay.
  # - `volume_based` — square-root market impact scaled by order size against
  #   average volume, for sizing studies where a large order moves the book.
  #
  # Slippage always moves *against* the taker. A model that sometimes improved
  # your fill would make backtests look better than reality.
  class MatchingEngine
    DEFAULT_SLIPPAGE_BPS = 5
    # Coefficient on the square-root impact model, in basis points.
    IMPACT_COEFFICIENT_BPS = 10

    def initialize(config = {})
      @config = (config || {}).with_indifferent_access
    end

    # @param order_type [String] MARKET | LIMIT | STOP_LOSS | STOP_LOSS_MARKET
    # @param limit_price [Numeric, nil]
    # @param market_price [Numeric] current LTP
    # @param transaction_type [String] BUY | SELL
    # @param quantity [Integer]
    # @param security_id [String]
    # @param exchange_segment [String, nil]
    # @return [Float, nil] fill price, or nil when the order cannot fill now
    def fill_price(order_type:, limit_price:, market_price:, transaction_type:, quantity:, security_id:,
                   exchange_segment: nil)
      return nil if market_price.blank? || market_price.to_f <= 0

      buy = transaction_type.to_s.casecmp('BUY').zero?
      market = market_price.to_f

      case order_type.to_s.upcase
      when 'MARKET', 'STOP_LOSS_MARKET'
        apply_slippage(market, buy, quantity, security_id, exchange_segment)
      when 'LIMIT', 'STOP_LOSS'
        limit = limit_price.to_f
        return nil unless limit.positive?
        # Only a marketable limit trades; otherwise it rests.
        return nil if buy ? limit < market : limit > market

        # A marketable limit fills at the better of limit and market, and does
        # not pay market-order slippage — it is providing the cross.
        buy ? [limit, market].min : [limit, market].max
      else
        apply_slippage(market, buy, quantity, security_id, exchange_segment)
      end
    end

    # How much of the remaining quantity fills on this pass.
    #
    # @param requested_qty [Integer]
    # @return [Integer] between 1 and requested_qty
    def fill_quantity(requested_qty, security_id: nil)
      qty = requested_qty.to_i
      return qty unless partial_fills_enabled?
      return qty if qty <= 1
      return qty if rand < fill_probability(security_id)

      min_fill = (qty * partial_fill_min_pct).ceil
      max_fill = [(qty * 0.8).floor, min_fill].max
      rand(min_fill..max_fill).clamp(1, qty)
    end

    private

    attr_reader :config

    def apply_slippage(market, buy, quantity, security_id, exchange_segment)
      slip = slippage_for(market, quantity, security_id, exchange_segment)
      price = buy ? market + slip : market - slip
      price.positive? ? price.round(2) : market.round(2)
    end

    def slippage_for(market, quantity, security_id, exchange_segment)
      case config[:slippage_model].to_s
      when 'none' then 0.0
      when 'spread_based' then spread_slippage(security_id, exchange_segment) || fixed_slippage(market)
      when 'volume_based' then volume_slippage(market, quantity, security_id, exchange_segment)
      else fixed_slippage(market)
      end
    end

    def fixed_slippage(market)
      bps = (config[:slippage_bps] || DEFAULT_SLIPPAGE_BPS).to_f
      market * (bps / 10_000.0)
    end

    # Half the live bid/ask spread, from the depth the feed caches.
    def spread_slippage(security_id, exchange_segment)
      return nil if security_id.blank? || exchange_segment.blank?

      tick = Live::TickCache.get(exchange_segment, security_id.to_s)
      depth = tick && (tick[:depth] || tick[:market_depth])
      best = Array(depth).first
      return nil unless best.is_a?(Hash)

      bid = (best[:bid_price] || best['bid_price']).to_f
      ask = (best[:ask_price] || best['ask_price']).to_f
      return nil unless bid.positive? && ask > bid

      ((ask - bid) / 2.0).round(2)
    end

    # Square-root market impact: doubling size costs ~1.4x, not 2x.
    def volume_slippage(market, quantity, security_id, exchange_segment)
      avg_volume = average_volume(security_id, exchange_segment)
      return fixed_slippage(market) unless avg_volume&.positive?

      impact_bps = IMPACT_COEFFICIENT_BPS * Math.sqrt(quantity.to_f / avg_volume)
      market * (impact_bps / 10_000.0)
    end

    def average_volume(security_id, exchange_segment)
      return nil if security_id.blank? || exchange_segment.blank?

      tick = Live::TickCache.get(exchange_segment, security_id.to_s)
      (tick && (tick[:volume] || tick[:avg_volume]))&.to_f
    end

    def partial_fills_enabled?
      config[:partial_fill_enabled].to_s == 'true' || config[:partial_fill_enabled] == true
    end

    def partial_fill_min_pct
      (config[:partial_fill_min_pct] || 0.3).to_f
    end

    def fill_probability(_security_id)
      (config[:fill_probability] || 1.0).to_f
    end
  end
end
