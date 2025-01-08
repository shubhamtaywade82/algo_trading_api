module AlertProcessors
  class IndexAlertProcessor < ApplicationService
    attr_reader :alert, :instrument, :security_symbol, :exchange

    def initialize(alert)
      @alert = alert
      @security_symbol = alert[:ticker]
      @exchange = alert[:exchange]
    end

    def call
      expiry = instrument.expiry_list.first
      option_chain = fetch_option_chain(expiry)
      best_strike = select_best_strike(option_chain)

      if best_strike
        option_type = alert[:action].downcase == "buy" ? "CE" : "PE"
        strike_price = best_strike[:strike_price]
        strike_instrument = fetch_instrument_for_strike(strike_price, expiry, option_type)

        place_order(strike_instrument, best_strike)
        @alert.update(status: "processed")
      else
        raise "Failed to find a suitable strike for trading"
      end
    rescue => e
      @alert.update(status: "failed", error_message: e.message)
      Rails.logger.error("Failed to process index alert: #{e}")
    end

    private

    # Fetch the instrument record
    def instrument
      @instrument ||= Instrument.find_by!(
        exchange: exchange,
        underlying_symbol: security_symbol,
        instrument_type: alert[:instrument_type] == "stock" ? "ES" : "INDEX"
      )
    rescue ActiveRecord::RecordNotFound
      raise "Instrument not found for #{security_symbol} in #{exchange}"
    end

    # Fetch option chain for the specified expiry
    def fetch_option_chain(expiry)
      instrument.fetch_option_chain(expiry)
    rescue => e
      raise "Failed to fetch option chain for #{security_symbol} with expiry #{expiry}: #{e.message}"
    end

    def fetch_instrument_for_strike(strike_price, expiry_date, option_type)
      Instrument.joins(:derivative)
                .where(
                  "instruments.segment = ? AND
                   instruments.underlying_symbol = ? AND
                   instruments.instrument = ? AND
                   derivatives.strike_price = ? AND
                   derivatives.option_type = ? AND
                   derivatives.expiry_date = ?",
                  "D", # Derivatives
                  security_symbol,
                  "OPTIDX", # Options Index
                  strike_price,
                  option_type.upcase,
                  expiry_date.to_date
                )
                .first!
    rescue ActiveRecord::RecordNotFound
      raise "Instrument not found for #{security_symbol}, strike #{strike_price}, expiry #{expiry_date}, and option type #{option_type}"
    end

    # Analyze and select the best strike for trading
    def select_best_strike(option_chain)
      chain_analyzer = Option::ChainAnalyzer.new(option_chain)
      analysis = chain_analyzer.analyze

      # Determine the desired option type (CE/PE) based on the action
      option_type = alert[:action].downcase == "buy" ? "ce" : "pe"

      strikes = option_chain[:oc].map do |strike, data|
        next unless data[option_type]
        {
          strike_price: strike.to_f,
          last_price: data[option_type]["last_price"].to_f,
          oi: data[option_type]["oi"].to_i,
          iv: data[option_type]["implied_volatility"].to_f,
          greeks: data[option_type]["greeks"]
        }
      end.compact

      # Select based on OI, IV, and Greeks (customizable logic)
      strikes.max_by do |s|
        s[:oi] * s[:iv] * (s.dig(:greeks, :delta).abs || 0.5) # Example scoring formula
      end
    end

    # Place the order for the selected strike
    def place_order(instrument, strike)
      available_balance = fetch_available_balance
      max_allocation = available_balance * 0.5 # Use 50% of available balance
      quantity = calculate_quantity(strike[:last_price], max_allocation, instrument.lot_size)

      order_data = {
        transactionType: "BUY",
        exchangeSegment: instrument.exchange_segment,
        productType: "INTRADAY",
        orderType: alert[:order_type].upcase,
        validity: "DAY",
        securityId: instrument.security_id,
        quantity: quantity,
        price: strike[:last_price],
        triggerPrice: alert[:stop_price] || strike[:last_price]
      }

      pp order_data
      Dhanhq::API::Orders.place(order_data)
    rescue => e
      raise "Failed to place order for instrument #{instrument.symbol_name}: #{e.message}"
    end

    # Fetch available balance from the API
    def fetch_available_balance
      Dhanhq::API::Funds.balance["availabelBalance"].to_f
    rescue => e
      raise "Failed to fetch available balance"
    end

    # Calculate the maximum quantity to trade
    def calculate_quantity(price, max_allocation, lot_size)
      max_quantity = (max_allocation / price).floor # Maximum quantity based on allocation
      adjusted_quantity = (max_quantity / lot_size) * lot_size # Adjust to nearest lot size

      [adjusted_quantity, lot_size].max # Ensure at least one lot
    end
  end
end
