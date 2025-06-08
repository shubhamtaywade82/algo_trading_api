# frozen_string_literal: true

# Calculates entry/ltp/pnl/percent/type for any position
#
# This service analyzes a trading position and calculates various metrics such as entry price, last traded price (LTP), profit and loss (P&L), percentage change, and the type of instrument (stock or option).
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
      entry = @pos['costPrice'].to_f
      ltp   = @pos['ltp'].to_f
      qty   = @pos['netQty'].abs
      side  = @pos['netQty'].to_i.positive? ? 1 : -1
      pnl   = (ltp - entry) * qty * side


      {
        entry_price: entry,
        ltp: ltp,
        exit_price: ltp,
        quantity: qty,
        pnl: pnl.round(2),
        pnl_pct: (pnl / (entry * qty).abs * 100).round(2),
        instrument_type: detect_instrument_type(@pos)
      }
    end

    private

    # Detects if the instrument is :stock or :option
    # @param [Hash] pos
    # @return [Symbol]
    def detect_instrument_type(pos)
      if pos['exchangeSegment'].include?('FNO') || pos['productType'] == 'INTRADAY'
        :option
      else
        :stock
      end
    end
  end
end
