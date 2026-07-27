# frozen_string_literal: true

module Llm
  module Tools
    # Recent OHLC candles with indicators, for market-structure questions.
    class Candles < Base
      delegates_to AI::Tools::DhanCandleTool

      description 'Fetch recent OHLC candles and derived indicators for a symbol, for trend and ' \
                  'market-structure analysis.'

      param :symbol, type: 'string', desc: 'Underlying symbol, e.g. NIFTY or RELIANCE'
      param :interval, type: 'string', desc: 'Candle interval, e.g. 5m, 15m, 1d'
      param :limit, type: 'integer', desc: 'How many candles to return (default 20)', required: false
    end
  end
end
