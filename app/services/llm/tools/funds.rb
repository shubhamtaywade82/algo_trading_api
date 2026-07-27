# frozen_string_literal: true

module Llm
  module Tools
    # Trading capital, used margin and the capital band that governs sizing.
    class Funds < Base
      delegates_to AI::Tools::FundsTool

      description 'Fetch available trading capital, used margin and the capital-band policy ' \
                  '(allocation %, risk per trade %, daily max loss %) used for position sizing.'
    end
  end
end
