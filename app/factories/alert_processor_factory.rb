# frozen_string_literal: true

class AlertProcessorFactory
  def self.build(alert)
    case alert.instrument_type
    when 'stock'
      AlertProcessors::Stock.new(alert)
    when 'index'
      AlertProcessors::Index.new(alert)
    else
      raise NotImplementedError, "Unsupported instrument type: #{alert.instrument_type}"
    end
  end
end
