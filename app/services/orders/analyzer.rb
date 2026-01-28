# frozen_string_literal: true

# Calculates entry/ltp/pnl/percent/type for any position
#
# Analyzes a trading position and returns entry price, LTP, P&L, percentage change, and instrument type.
#
# @example
#   analyzer = Orders::Analyzer.new(position)
#   result = analyzer.call
#   puts result[:pnl] # Outputs the calculated P&L
#   puts result[:instrument_type] # Outputs :stock or :option based on the position type
module Orders
  class Analyzer < ApplicationService
    # @param [Hash] position
    def initialize(position)
      @pos = position.with_indifferent_access
    end

    def call
      entry_price = PriceMath.round_tick(@pos['costPrice'].to_f)
      quantity    = @pos['netQty'].abs
      long        = @pos['netQty'].to_i.positive?
      instrument_type = detect_instrument_type(@pos)
      ltp = fetch_ltp
      return {} unless ltp && entry_price.positive? && quantity.positive?

      side        = long ? 1 : -1
      pnl         = (ltp - entry_price) * quantity * side
      pnl_pct     = PriceMath.round_tick((pnl / (entry_price * quantity) * 100))

      {
        entry_price: entry_price,
        ltp: ltp,
        exit_price: ltp,
        quantity: quantity,
        pnl: PriceMath.round_tick(pnl),
        pnl_pct: pnl_pct,
        instrument_type: instrument_type,
        order_type: default_order_type(instrument_type, quantity),
        long: long
      }
    rescue StandardError => e
      Rails.logger.error("[Orders::Analyzer] Failed to analyze position: #{e.message}")
      {}
    end

    private

    def fetch_ltp
      MarketCache.read_ltp(@pos['exchangeSegment'], @pos['securityId'])&.then do |ltp|
        PriceMath.round_tick(ltp)
      end || fallback_ltp&.then do |ltp|
               PriceMath.round_tick(ltp)
             end
    end

    def fallback_ltp
      @pos['ltp'].to_f if @pos['ltp'].to_f.positive?
    end

    def default_order_type(instrument_type, qty)
      # Could be enhanced with liquidity metrics or orderbook depth later
      instrument_type == :option && qty <= 75 ? 'MARKET' : 'LIMIT'
      'MARKET'
    end

    # Detects if the instrument is :stock or :option
    # @param [Hash] pos
    # @return [Symbol]
    def detect_instrument_type(pos)
      exchange_segment = pos['exchangeSegment'].to_s.upcase
      product_type     = pos['productType'].to_s.upcase
      trading_symbol   = pos['tradingSymbol'].to_s.upcase

      # 1. Option instruments based on Exchange Segment or Symbol
      return :option if %w[NSE_FNO BSE_FNO MCX_COMM].include?(exchange_segment) &&
                        (trading_symbol.include?('CE') || trading_symbol.include?('PE'))

      # 2. Currency or Commodity Futures/Options are also treated as options
      return :option if %w[NSE_CURRENCY BSE_CURRENCY MCX_COMM].include?(exchange_segment)

      # 3. All IDX_I like NIFTY or BANKNIFTY (spot index values), treat based on symbol
      return :index if exchange_segment == 'IDX_I'

      # 4. Equity Stocks (delivery or intraday)
      return :stock if %w[NSE_EQ BSE_EQ].include?(exchange_segment)

      # 5. Fallback: if unknown but intraday, still assume it's a stock unless CE/PE is present
      if product_type == 'INTRADAY'
        return trading_symbol.include?('CE') || trading_symbol.include?('PE') ? :option : :stock
      end

      # 6. Final fallback
      :unknown
    end
  end
end
