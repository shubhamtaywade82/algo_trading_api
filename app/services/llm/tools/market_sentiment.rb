# frozen_string_literal: true

module Llm
  module Tools
    # Aggregate bias from the option chain and price structure.
    class MarketSentiment < Base
      delegates_to AI::Tools::MarketSentimentTool

      description 'Fetch the aggregate market bias (bullish / bearish / neutral) for an index, ' \
                  'derived from option-chain positioning and price structure.'

      param :symbol, type: 'string', desc: 'Index symbol, e.g. NIFTY'
    end
  end
end
