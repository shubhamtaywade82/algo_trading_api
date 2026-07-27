# frozen_string_literal: true

module Llm
  module Tools
    # Open positions with P&L.
    class Positions < Base
      delegates_to AI::Tools::PositionsTool

      description 'Fetch current trading positions with quantity, entry, LTP and P&L.'

      param :filter, type: 'string', desc: "Which positions to return: 'all', 'open' or 'closed'", required: false
    end
  end
end
