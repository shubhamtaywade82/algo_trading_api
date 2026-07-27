# frozen_string_literal: true

module Llm
  module Tools
    # Live option chain, IV rank, PCR and ranked strikes for an NSE index.
    class OptionChain < Base
      delegates_to AI::Tools::OptionChainTool

      description 'Fetch and analyse the option chain for an NSE index (NIFTY, BANKNIFTY, FINNIFTY). ' \
                  'Returns spot, IV rank, PCR, sentiment, the best strike and the nearest strikes.'

      param :symbol, type: 'string', desc: 'Index symbol: NIFTY, BANKNIFTY or FINNIFTY'
      param :expiry, type: 'string', desc: 'Expiry date YYYY-MM-DD; defaults to the nearest', required: false
      param :signal_type, type: 'string', desc: 'Direction to rank strikes for: ce (bullish) or pe (bearish)',
                          required: false
    end
  end
end
