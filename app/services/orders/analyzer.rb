# frozen_string_literal: true

module Orders
  class Analyzer < ApplicationService
    def initialize(position)
      @pos = position.with_indifferent_access
    end

    def call
      entry = @pos['buyAvg'].to_f
      ltp   = @pos['ltp'].to_f
      qty   = @pos['netQty'].abs
      side  = @pos['netQty'].to_i.positive? ? 1 : -1
      pnl   = (ltp - entry) * qty * side

      {
        entry_price: entry,
        ltp: ltp,
        quantity: qty,
        pnl: pnl.round(2),
        pnl_pct: (pnl / (entry * qty).abs * 100).round(2),
        instrument_type: detect_instrument_type(@pos)
      }
    end

    private

    def detect_instrument_type(pos)
      if pos['exchangeSegment'].include?('FNO') || pos['productType'] == 'INTRADAY'
        :option
      else
        :stock
      end
    end
  end
end
