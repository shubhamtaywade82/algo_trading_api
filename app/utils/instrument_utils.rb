# frozen_string_literal: true

module InstrumentUtils
  def self.find_instrument_by_symbol(symbol, segment, exchange)
    Instrument.find_by!(
      underlying_symbol: symbol,
      segment: segment,
      exchange: exchange
    )
  rescue ActiveRecord::RecordNotFound
    raise "Instrument not found for symbol: #{symbol}, segment: #{segment}, exchange: #{exchange}"
  end

  def self.find_instrument_with_options(strike_price, expiry_date, option_type)
    Instrument.joins(:derivative).find_by!(
      'derivatives.strike_price = ? AND derivatives.option_type = ? AND derivatives.expiry_date = ?',
      strike_price, option_type, expiry_date
    )
  rescue ActiveRecord::RecordNotFound
    raise "Option not found for strike: #{strike_price}, expiry: #{expiry_date}, type: #{option_type}"
  end
end
