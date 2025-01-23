# frozen_string_literal: true

module AlertProcessors
  class Index < Base
    attr_reader :alert, :exchange

    def call
      expiry = instrument.expiry_list.first
      option_chain = fetch_option_chain(expiry)
      best_strike = select_best_strike(option_chain)

      raise 'Failed to find a suitable strike for trading' unless best_strike

      option_type = alert[:action].downcase == 'buy' ? 'CE' : 'PE'
      strike_price = best_strike[:strike_price]
      strike_instrument = fetch_instrument_for_strike(strike_price, expiry, option_type)

      place_order(strike_instrument, best_strike)
      @alert.update(status: 'processed')
    rescue StandardError => e
      @alert.update(status: 'failed', error_message: e.message)
      Rails.logger.error("Failed to process index alert: #{e}")
    end

    private

    # Fetch option chain for the specified expiry
    def fetch_option_chain(expiry)
      instrument.fetch_option_chain(expiry)
    rescue StandardError => e
      raise "Failed to fetch option chain for #{alert[:ticker]} with expiry #{expiry}: #{e.message}"
    end

    def fetch_instrument_for_strike(strike_price, expiry_date, option_type)
      instrument.derivatives.find_by(strike_price: strike_price, expiry_date: expiry_date, option_type: option_type)
    rescue ActiveRecord::RecordNotFound
      raise "Instrument not found for #{alert[:ticker]}, strike #{strike_price}, expiry #{expiry_date}, and option type #{option_type}"
    end

    # Analyze and select the best strike for trading
    # def select_best_strike(option_chain)
    #   chain_analyzer = Option::ChainAnalyzer.new(option_chain)
    #   chain_analyzer.analyze

    #   # Determine the desired option type (CE/PE) based on the action
    #   option_type = alert[:action].downcase == 'buy' ? 'ce' : 'pe'

    #   strikes = option_chain[:oc].filter_map do |strike, data|
    #     next unless data[option_type]

    #     {
    #       strike_price: strike.to_i,
    #       last_price: data[option_type]['last_price'].to_f,
    #       oi: data[option_type]['oi'].to_i,
    #       iv: data[option_type]['implied_volatility'].to_f,
    #       greeks: data[option_type]['greeks']
    #     }
    #   end

    #   # Select based on OI, IV, and Greeks (customizable logic)
    #   strikes.max_by do |s|
    #     s[:oi] * s[:iv] * (s.dig(:greeks, :delta).abs || 0.5) # Example scoring formula
    #   end
    # end

    # Analyze and select the best strike for trading
    def select_best_strike(option_chain)
      chain_analyzer = Option::ChainAnalyzer.new(option_chain)
      analysis = chain_analyzer.analyze

      # Determine the desired option type (CE/PE) based on the action
      option_type = alert[:action].downcase == 'buy' ? 'ce' : 'pe'

      strikes = option_chain[:oc].filter_map do |strike, data|
        next unless data[option_type]

        {
          strike_price: strike.to_i,
          last_price: data[option_type]['last_price'].to_f,
          oi: data[option_type]['oi'].to_i,
          iv: data[option_type]['implied_volatility'].to_f,
          greeks: data[option_type]['greeks']
        }
      end

      # Select based on combined metrics using analysis results
      strikes.max_by do |s|
        score = s[:oi] * s[:iv] * (s.dig(:greeks, :delta).abs || 0.5) # Existing scoring formula
        score += 1 if s[:strike_price] == analysis[:max_pain] # Favor max pain level
        score += 1 if s[:strike_price] == analysis[:support_resistance][:support] # Favor support
        score += 1 if s[:strike_price] == analysis[:support_resistance][:resistance] # Favor resistance
        score
      end
    end

    # Place the order for the selected strike
    def place_order(instrument, strike)
      available_balance = fetch_available_balance
      max_allocation = available_balance * 0.5 # Use 50% of available balance
      quantity = calculate_quantity(strike[:last_price], max_allocation, instrument.lot_size)

      if available_balance < (quantity * strike[:last_price])
        return ErrorLogger.log_error("Insufficient balance: #{available_balance - (quantity * strike[:last_price])}")
      end

      order_data = {
        transactionType: Dhanhq::Constants::BUY,
        exchangeSegment: instrument.exchange_segment,
        productType: Dhanhq::Constants::MARGIN,
        orderType: alert[:order_type].upcase,
        validity: Dhanhq::Constants::DAY,
        securityId: instrument.security_id,
        quantity: quantity,
        price: strike[:last_price],
        triggerPrice: strike[:last_price].to_f || alert[:stop_price].to_f
      }

      if ENV['PLACE_ORDER'] == 'true'
        executed_order = Dhanhq::API::Orders.place(order_data)
        Rails.logger.info("#{executed_order}, #{alert}")
      else
        Rails.logger.info("PLACE_ORDER is disabled. Order parameters: #{order_data}")
      end
      # executed_order = Dhanhq::API::Orders.place(order_data)
      # dhan_order = OrdersService.fetch_order(executed_order[:orderId])
      # order = Order.new(
      #   dhan_order_id: dhan_order[:orderId],
      #   transaction_type: dhan_order[:transactionType],
      #   product_type: dhan_order[:productType],
      #   order_type: dhan_order[:orderType],
      #   validity: dhan_order[:validity],
      #   exchange_segment: dhan_order[:exchangeSegment],
      #   security_id: dhan_order[:securityId],
      #   quantity: dhan_order[:quantity],
      #   disclosed_quantity: dhan_order[:disclosedQuantity],
      #   price: dhan_order[:price],
      #   trigger_price: dhan_order[:triggerPrice],
      #   bo_profit_value: dhan_order[:boProfitValue],
      #   bo_stop_loss_value: dhan_order[:boStopLossValue],
      #   ltp: dhan_order[:price],
      #   order_status: dhan_order[:orderStatus],
      #   filled_qty: dhan_order[:filled_qty],
      #   average_traded_price: (dhan_order[:price] * dhan_order[:quantity]),
      #   alert_id: alert[:id]
      # )
      # order.save
    rescue StandardError => e
      raise "Failed to place order for instrument #{instrument.symbol_name}: #{e.message}"
    end

    # Fetch available balance from the API
    def fetch_available_balance
      Dhanhq::API::Funds.balance['availabelBalance'].to_f
    rescue StandardError
      raise 'Failed to fetch available balance'
    end

    # Calculate the maximum quantity to trade
    def calculate_quantity(price, max_allocation, lot_size)
      max_quantity = (max_allocation / price).floor # Maximum quantity based on allocation
      adjusted_quantity = (max_quantity / lot_size) * lot_size # Adjust to nearest lot size

      [adjusted_quantity, lot_size].max # Ensure at least one lot
    end
  end
end
