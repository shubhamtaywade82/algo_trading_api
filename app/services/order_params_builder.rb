# frozen_string_literal: true

class OrderParamsBuilder
  def self.build(alert:, instrument:, funds:, leverage: 1.0, utilization: 0.3)
    quantity = calculate_quantity(instrument, funds, leverage, utilization)
    {
      transactionType: alert[:action].upcase,
      orderType: alert[:order_type].upcase,
      productType: alert[:strategy_type] == 'intraday' ? 'INTRADAY' : 'CNC',
      validity: 'DAY',
      securityId: instrument.security_id,
      exchangeSegment: instrument.exchange_segment,
      quantity: quantity,
      price: alert[:current_price]
    }
  end

  def self.calculate_quantity(instrument, funds, leverage, utilization)
    max_funds = funds * utilization * leverage
    (max_funds / instrument.lot_size).floor
  end
end
