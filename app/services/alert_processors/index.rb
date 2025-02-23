# frozen_string_literal: true

module AlertProcessors
  # Index processes TradingView alerts for index instruments.
  # It fetches the option chain, selects an optimal strike, retrieves
  # the corresponding derivative instrument, and places an order if funds allow.
  class Index < Base
    ATM_RANGE_PERCENT = 0.02 # ±2% range for ATM selection
    MIN_OI_THRESHOLD = 50_000 # Ensure sufficient liquidity

    # Main entry point for processing an index alert.
    # 1) Grabs the first expiry for the index.
    # 2) Fetches the option chain.
    # 3) Selects the best strike based on combined metrics (OI, IV, Greeks, etc.).
    # 4) Determines the option type (CE/PE) from the alert action (buy/sell).
    # 5) Finds the derivative instrument matching strike + expiry + option_type.
    # 6) Places an order (if PLACE_ORDER=true).
    # 7) Updates alert status to 'processed' upon success.
    #
    # If any step fails, it rescues StandardError, updates the alert status
    # to 'failed', logs the error, and bubbles up a message.
    #
    # @return [void]
    def call
      Rails.logger.info("Processing index alert: #{alert.inspect}")
      process_index_strategy
      @alert.update(status: 'processed')
    rescue StandardError => e
      @alert.update(status: 'failed', error_message: e)
      Rails.logger.error("Failed to process index alert: #{e}")
    end

    private

    def process_index_strategy
      expiry = instrument.expiry_list.first
      option_chain = fetch_option_chain(expiry)

      alert[:action].upcase

      chain_analyzer = Option::ChainAnalyzer.new(option_chain)
      analysis = chain_analyzer.analyze

      # Use Strategy Suggester to find the best affordable strategy
      suggester = Option::StrategySuggester.new(option_chain, { index_symbol: alert[:ticker] })
      strategy_recommendation = suggester.suggest(analysis: analysis)

      strategy_recommendation[:strategies].first
      # best_strike = select_best_strike(option_chain)

      selected_strategy = select_best_strategy(strategy_recommendation)
      raise 'No valid strategy found' if selected_strategy.nil?

      Rails.logger.info("Selected strategy: #{selected_strategy.inspect}")
      # raise 'Failed to find a suitable strike for trading' unless best_strike

      # option_type = alert[:action].downcase == 'buy' ? 'CE' : 'PE'
      # strike_price = best_strike[:strike_price]
      # strike_instrument = fetch_instrument_for_strike(strike_price, expiry, option_type)
      execute_trade(selected_strategy, expiry)

      # build_order_payload(selected_strategy)
      # place_order(strike_instrument, best_strike)
    end

    # Fetches the option chain for a given expiry date.
    # Raises a StandardError if the API call or data parsing fails.
    #
    # @param expiry [String, Date, Time] The expiry date for the option chain.
    # @return [Hash] The option chain data structure.
    def fetch_option_chain(expiry)
      instrument.fetch_option_chain(expiry)
    rescue StandardError => e
      raise "Failed to fetch option chain for #{alert[:ticker]} with expiry #{expiry}: #{e.message}"
    end

    def select_best_strategy(strategy_recommendation)
      # bearish_strategies = ['Long Put', 'Bear Put Spread', 'Short Call']
      # bullish_strategies = ['Long Call', 'Bull Call Spread', 'Short Put']

      buy_strategies = ['Long Call', 'Bull Call Spread', 'Short Put']
      sell_strategies = ['Long Put', 'Bear Put Spread', 'Short Call']

      # sentiment = strategy_recommendation[:index_details][:sentiment]
      action = alert[:action].upcase
      strategies = strategy_recommendation[:strategies]

      # if sentiment[:bullish]
      #   strategies.find { |s| bullish_strategies.include?(s[:name]) }
      # elsif sentiment[:bearish]
      #   strategies.find { |s| bearish_strategies.include?(s[:name]) }
      # else
      #   strategies.first # Default to first available strategy
      # end
      if action == 'BUY'
        strategies.find { |s| buy_strategies.include?(s[:name]) } || strategies.first
      elsif action == 'SELL'
        strategies.find { |s| sell_strategies.include?(s[:name]) } || strategies.first
      else
        strategies.first # Default to first available strategy
      end
    end

    def execute_trade(strategy, expiry)
      trade_legs = strategy[:trade_legs]
      trade_legs.each do |trade_leg|
        strike_instrument = fetch_instrument_for_strike(
          trade_leg[:strike_price], expiry, trade_leg[:option_type]
        )
        order_params = build_order_payload(trade_leg, strike_instrument)
        place_order(order_params)
      end
    end

    # Selects the "best" strike from the option chain using a scoring formula.
    # The chain_analyzer may return additional metrics like max_pain, support, or resistance.
    #
    # @param option_chain [Hash] The option chain data structure.
    # @return [Hash, nil] The selected strike's data, or nil if none found.
    def select_best_strike(option_chain)
      chain_analyzer = Option::ChainAnalyzer.new(option_chain)
      analysis = chain_analyzer.analyze

      # CE if alert[:action] == 'buy', else PE
      option_key = alert[:action].downcase == 'buy' ? 'ce' : 'pe'

      # Build an array of potential strikes with relevant data
      strikes = option_chain[:oc].filter_map do |strike, data|
        next unless data[option_key]

        {
          strike_price: strike.to_i,
          last_price: data[option_key]['last_price'].to_f,
          oi: data[option_key]['oi'].to_i,
          iv: data[option_key]['implied_volatility'].to_f,
          greeks: data[option_key]['greeks']
        }
      end

      # Score each strike and pick the max
      strikes.max_by do |s|
        score = s[:oi] * s[:iv] * (s.dig(:greeks, :delta).abs || 0.5) # Existing scoring formula
        score += 1 if s[:strike_price] == analysis[:max_pain] # Favor max pain level
        score += 1 if s[:strike_price] == analysis[:support_resistance][:support] # Favor support
        score += 1 if s[:strike_price] == analysis[:support_resistance][:resistance] # Favor resistance
        score
      end
    end

    # Determines whether this is a 'CE' (call) or 'PE' (put),
    # based on the alert action (buy vs. sell).
    #
    # @return [String] 'CE' if buy, otherwise 'PE'
    def resolve_option_type
      alert[:action].downcase == 'buy' ? 'CE' : 'PE'
    end

    # Finds the matching derivative instrument for the selected strike.
    # Raises StandardError if the record isn't found.
    #
    # @param strike_price [Float, Integer] The option strike price.
    # @param expiry_date [String, Date]    The expiry date for the option.
    # @param option_type [String]         'CE' or 'PE'.
    # @return [Derivative] The matching derivative record.
    def fetch_instrument_for_strike(strike_price, expiry_date, option_type)
      instrument.derivatives.find_by(strike_price: strike_price, expiry_date: expiry_date, option_type: option_type)
    rescue ActiveRecord::RecordNotFound
      raise "Derivative Instrument not found for #{alert[:ticker]}, strike #{strike_price}, " \
            "expiry #{expiry_date}, and option type #{option_type}"
    end

    # Places an order for the selected strike. If PLACE_ORDER=true, it calls
    # the Dhanhq API to place the order. Otherwise, it logs a message but does not place an order.
    #
    # @param instrument [Derivative] The derivative instrument for this strike.
    # @param strike [Hash]  The hash describing the best strike data (last_price, etc.).
    # @return [void]
    # def place_order(derivative_instrument, strike)
    #   available_balance = fetch_available_balance
    #   max_allocation = available_balance * 0.5 # Use 50% of available balance
    #   quantity = calculate_quantity(strike[:last_price], max_allocation, derivative_instrument.lot_size)
    #   total_order_cost = quantity * strike[:last_price]

    #   if available_balance < total_order_cost
    #     shortfall = total_order_cost - available_balance
    #     raise "Insufficient funds ₹#{shortfall.round(2)}: Required ₹#{total_order_cost}, " \
    #           "Available ₹#{available_balance}"
    #   end

    #   order_data = {
    #     transactionType: Dhanhq::Constants::BUY,
    #     exchangeSegment: derivative_instrument.exchange_segment,
    #     productType: Dhanhq::Constants::MARGIN,
    #     orderType: alert[:order_type].upcase,
    #     validity: Dhanhq::Constants::DAY,
    #     securityId: derivative_instrument.security_id,
    #     quantity: quantity,
    #     price: strike[:last_price],
    #     triggerPrice: strike[:last_price].to_f || alert[:stop_price].to_f
    #   }

    #   if ENV['PLACE_ORDER'] == 'true'
    #     executed_order = Dhanhq::API::Orders.place(order_data)
    #     Rails.logger.info("Executed order: #{executed_order}, alert: #{alert}")
    #   else
    #     Rails.logger.info("PLACE_ORDER is disabled. Order parameters: #{order_data}")
    #   end
    # rescue StandardError => e
    #   raise "Failed to place order for derivative_instrument #{derivative_instrument.symbol_name}: #{e.message}"
    # end

    # **Step 7: Place Order**
    def place_order(order_params)
      if ENV['PLACE_ORDER'] == 'true'
        executed_order = Dhanhq::API::Orders.place(order_params)
        Rails.logger.info("Order placed successfully: #{executed_order}")
      else
        Rails.logger.info("PLACE_ORDER is disabled. Order parameters: #{order_params}")
      end
    rescue StandardError => e
      raise "Failed to place order: #{e.message}"
    end

    # Calculates the quantity to trade, ensuring it aligns with the lot size.
    # Uses at least one lot, if the computed max_allocation permits.
    #
    # @param price [Float]            The last price of the strike.
    # @param max_allocation [Float]   The maximum funds to allocate.
    # @param lot_size [Integer, Float] The contract lot size for this derivative.
    # @return [Integer] The final quantity to trade.
    def calculate_quantity(price, lot_size)
      max_allocation = fetch_available_balance * 0.5
      max_quantity = (max_allocation / price).floor
      adjusted_quantity = (max_quantity / lot_size) * lot_size
      [adjusted_quantity, lot_size].max
    end

    def build_order_payload(trade_leg, derivative_instrument)
      {
        transactionType: trade_leg[:action],
        orderType: alert[:order_type].upcase,
        productType: Dhanhq::Constants::MARGIN,
        validity: Dhanhq::Constants::DAY,
        securityId: derivative_instrument.security_id,
        exchangeSegment: derivative_instrument.exchange_segment,
        quantity: calculate_quantity(trade_leg[:ltp], derivative_instrument.lot_size)
      }
    end

    # @!attribute [r] alert
    #   @return [Hash, ActionController::Parameters] The current alert data.
    #
    # @!method instrument
    #   @return [Instrument] the base instrument model used by this processor
    #
    # Both `alert` and `instrument` are inherited from the `Base` class in
    # AlertProcessors or included modules, so they are not explicitly defined here.
  end
end
