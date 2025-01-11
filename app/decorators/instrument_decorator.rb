# frozen_string_literal: true

class InstrumentDecorator < SimpleDelegator
  def formatted_name
    "[#{exchange}] #{symbol_name} - #{segment}"
  end
end
