# frozen_string_literal: true

# Maps derivative instrument codes (FUTIDX, OPTIDX, etc.) to their underlying type (INDEX, EQUITY).
# Used when resolving instrument_id for derivative rows: OPTIDX on NIFTY → find Instrument with
# instrument='INDEX' and underlying_symbol='NIFTY'.
module InstrumentTypeMapping
  PARENT_TO_CHILDREN = {
    'INDEX' => %w[FUTIDX OPTIDX],
    'EQUITY' => %w[FUTSTK OPTSTK],
    'FUTCOM' => %w[OPTFUT],
    'FUTCUR' => %w[OPTCUR]
  }.freeze

  CHILD_TO_PARENT =
    PARENT_TO_CHILDREN.flat_map { |parent, kids| kids.map { |kid| [kid, parent] } }.to_h.freeze

  module_function

  def underlying_for(code)
    return nil if code.blank?

    CHILD_TO_PARENT[code.to_s] || code.to_s
  end
end
