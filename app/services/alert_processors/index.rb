# frozen_string_literal: true

module AlertProcessors
  # Index processes TradingView alerts for index instruments.
  # It fetches the option chain, runs the advanced Option::ChainAnalyzer (with previous_* usage),
  # and decides whether or not to execute a trade based on the final trend:
  # - If the chain analysis trend is 'neutral', we skip the trade
  # - If it's 'bullish' or 'bearish', we proceed
  #
  # Then it picks a strike (CE or PE) based on alert[:action] (BUY => CE, SELL => PE) and places
  # an order if we find a valid derivative instrument.
  class Index < Base
    ATM_RANGE_PERCENT = 0.02 # ±2% range for ATM selection
    MIN_OI_THRESHOLD = 50_000 # Ensure sufficient liquidity

    # Main entry point for processing an index alert.
    #
    # Steps:
    #   1) Grab the first expiry for the index
    #   2) Fetch the option chain
    #   3) Build a ChainAnalyzer with expiry, underlying_spot, historical_data
    #   4) Analyze to get best_ce_strike, best_pe_strike, trend, volatility, etc.
    #   5) If the trend is 'neutral', skip trade
    #   6) If alert[:action] == 'BUY', pick best_ce_strike, else best_pe_strike
    #   7) Attempt to place an order for that strike
    #   8) Mark alert as processed
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
      # 1) Identify the first expiry
      expiry = instrument.expiry_list.first

      # 2) Fetch real-time option chain from the instrument
      option_chain = fetch_option_chain(expiry)

      # 3) Gather historical data for advanced analysis
      #    (We've already got an example from your code: 5-day daily data)
      historical_data = fetch_historical_data

      # 4) Build ChainAnalyzer with new parameters
      chain_analyzer = Option::ChainAnalyzer.new(
        option_chain,
        expiry: expiry,
        underlying_spot: ltp,
        historical_data: historical_data
      )

      analysis_result = chain_analyzer.analyze(
        strategy_type: alert[:strategy_type],
        instrument_type: segment_from_alert_type(alert[:instrument_type])
      )

      # 5) If trend is neutral, skip trade
      if analysis_result[:trend] == 'neutral'
        msg = "Trend is neutral for #{instrument.display_name}. Skipping trade."
        Rails.logger.info(msg)
        # Record the skip reason in status & error_message
        alert.update!(status: 'skipped', error_message: msg)
        return
      end

      # 6) Decide if we want to buy CE (if alert[:action] == 'BUY') or buy PE (if 'SELL')
      #    or if your logic is reversed, adapt accordingly
      #    We'll assume a simple approach: BUY => best_ce_strike, SELL => best_pe_strike
      action = alert[:action].to_s.upcase
      best_strike =
        if action == 'BUY'
          analysis_result[:best_ce_strike]
        elsif action == 'SELL'
          analysis_result[:best_pe_strike]
        end

      if best_strike.nil?
        msg = "No best strike found for action=#{action}. Skipping."
        Rails.logger.info(msg)
        alert.update!(status: 'skipped', error_message: msg)
        return
      end

      # 7) Attempt to find the matching derivative instrument for the chosen strike
      #    e.g. CE if alert[:action] == 'BUY', else PE if 'SELL'
      #    or if you want more advanced logic, adapt
      option_type = (action == 'BUY' ? 'CE' : 'PE')
      strike_instrument = fetch_instrument_for_strike(best_strike[:strike_price], expiry, option_type)

      if strike_instrument.nil?
        msg = "No derivative instrument found for #{instrument.display_name}, " \
              "strike=#{best_strike[:strike_price]}, expiry=#{expiry}, type=#{option_type}. Skipping."
        Rails.logger.info(msg)
        alert.update!(status: 'skipped', error_message: msg)
        return
      end

      # 8) Build an order payload and place the order
      order_params = build_order_payload(best_strike, strike_instrument)
      place_order(order_params)
      # # Use Strategy Suggester to find the best affordable strategy
      # suggester = Option::StrategySuggester.new(option_chain, { index_symbol: alert[:ticker] })
      # strategy_recommendation = suggester.suggest(analysis: analysis)

      # strategy_recommendation[:strategies].first
      # # best_strike = select_best_strike(option_chain)

      # selected_strategy = select_best_strategy(strategy_recommendation)
      # raise 'No valid strategy found' if selected_strategy.nil?

      # Rails.logger.info("Selected strategy: #{selected_strategy.inspect}")
      # # raise 'Failed to find a suitable strike for trading' unless best_strike

      # # option_type = alert[:action].downcase == 'buy' ? 'CE' : 'PE'
      # # strike_price = best_strike[:strike_price]
      # # strike_instrument = fetch_instrument_for_strike(strike_price, expiry, option_type)
      # execute_trade(selected_strategy, expiry)

      # # build_order_payload(selected_strategy)
      # # place_order(strike_instrument, best_strike)
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

    # **Fetch basic historical data** e.g. last 5 daily bars for momentum
    def fetch_historical_data
      Dhanhq::API::Historical.daily(
        securityId: instrument.security_id,
        exchangeSegment: instrument.exchange_segment,
        instrument: instrument.instrument_type,
        fromDate: 5.days.ago.to_date.to_s,
        toDate: Date.yesterday.to_s
      )
    rescue StandardError
      []
    end

    # Finds the matching derivative instrument for the selected strike.
    # Raises StandardError if the record isn't found.
    #
    # @param strike_price [Float, Integer] The option strike price.
    # @param expiry_date [String, Date]    The expiry date for the option.
    # @param option_type [String]         'CE' or 'PE'.
    # @return [Derivative] The matching derivative record.
    def fetch_instrument_for_strike(strike_price, expiry_date, option_type)
      derivative = instrument.derivatives.find_by(
        strike_price: strike_price,
        expiry_date: expiry_date,
        option_type: option_type
      )
      unless derivative
        Rails.logger.info("No derivative instrument found for #{instrument.display_name}, " \
                          "strike=#{strike_price}, expiry=#{expiry_date}, type=#{option_type}")
      end
      derivative
    end

    # **Construct the order parameters** for placing an order
    #   - We buy if action is 'BUY', else we sell
    #   - We set quantity by calling a helper that respects available funds
    def build_order_payload(best_strike, derivative_instrument)
      action = alert[:action].to_s.upcase # 'BUY' or 'SELL'

      {
        transactionType: action,
        orderType: alert[:order_type].to_s.upcase,
        productType: Dhanhq::Constants::MARGIN,
        validity: Dhanhq::Constants::DAY,
        securityId: derivative_instrument.security_id,
        exchangeSegment: derivative_instrument.exchange_segment,
        quantity: calculate_quantity(best_strike[:last_price], derivative_instrument.lot_size)
      }
    end

    # **Step 7: Place Order**
    def place_order(order_params)
      if ENV['PLACE_ORDER'] == 'true'
        executed_order = Dhanhq::API::Orders.place(order_params)
        msg = "Order placed successfully: #{executed_order}"
        Rails.logger.info(msg)
        # Optionally update alert to log the successful order result:
        alert.update!(error_message: msg)
      else
        msg = "PLACE_ORDER is disabled. Order parameters: #{order_params}"
        Rails.logger.info(msg)
        # We can mark as 'skipped' or 'processed' since no actual order is placed
        alert.update!(status: 'skipped', error_message: msg)
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

    # def select_best_strategy(strategy_recommendation)
    #   # bearish_strategies = ['Long Put', 'Bear Put Spread', 'Short Call']
    #   # bullish_strategies = ['Long Call', 'Bull Call Spread', 'Short Put']

    #   buy_strategies = ['Long Call', 'Bull Call Spread', 'Short Put']
    #   sell_strategies = ['Long Put', 'Bear Put Spread', 'Short Call']

    #   # sentiment = strategy_recommendation[:index_details][:sentiment]
    #   action = alert[:action].upcase
    #   strategies = strategy_recommendation[:strategies]

    #   # if sentiment[:bullish]
    #   #   strategies.find { |s| bullish_strategies.include?(s[:name]) }
    #   # elsif sentiment[:bearish]
    #   #   strategies.find { |s| bearish_strategies.include?(s[:name]) }
    #   # else
    #   #   strategies.first # Default to first available strategy
    #   # end
    #   if action == 'BUY'
    #     strategies.find { |s| buy_strategies.include?(s[:name]) } || strategies.first
    #   elsif action == 'SELL'
    #     strategies.find { |s| sell_strategies.include?(s[:name]) } || strategies.first
    #   else
    #     strategies.first # Default to first available strategy
    #   end
    # end

    # def execute_trade(strategy, expiry)
    #   trade_legs = strategy[:trade_legs]
    #   trade_legs.each do |trade_leg|
    #     strike_instrument = fetch_instrument_for_strike(
    #       trade_leg[:strike_price], expiry, trade_leg[:option_type]
    #     )
    #     order_params = build_order_payload(trade_leg, strike_instrument)
    #     place_order(order_params)
    #   end
    # end

    # # Selects the "best" strike from the option chain using a scoring formula.
    # # The chain_analyzer may return additional metrics like max_pain, support, or resistance.
    # #
    # # @param option_chain [Hash] The option chain data structure.
    # # @return [Hash, nil] The selected strike's data, or nil if none found.
    # def select_best_strike(option_chain)
    #   chain_analyzer = Option::ChainAnalyzer.new(option_chain)
    #   analysis = chain_analyzer.analyze

    #   # CE if alert[:action] == 'buy', else PE
    #   option_key = alert[:action].downcase == 'buy' ? 'ce' : 'pe'

    #   # Build an array of potential strikes with relevant data
    #   strikes = option_chain[:oc].filter_map do |strike, data|
    #     next unless data[option_key]

    #     {
    #       strike_price: strike.to_i,
    #       last_price: data[option_key]['last_price'].to_f,
    #       oi: data[option_key]['oi'].to_i,
    #       iv: data[option_key]['implied_volatility'].to_f,
    #       greeks: data[option_key]['greeks']
    #     }
    #   end

    #   # Score each strike and pick the max
    #   strikes.max_by do |s|
    #     score = s[:oi] * s[:iv] * (s.dig(:greeks, :delta).abs || 0.5) # Existing scoring formula
    #     score += 1 if s[:strike_price] == analysis[:max_pain] # Favor max pain level
    #     score += 1 if s[:strike_price] == analysis[:support_resistance][:support] # Favor support
    #     score += 1 if s[:strike_price] == analysis[:support_resistance][:resistance] # Favor resistance
    #     score
    #   end
    # end

    # # Determines whether this is a 'CE' (call) or 'PE' (put),
    # # based on the alert action (buy vs. sell).
    # #
    # # @return [String] 'CE' if buy, otherwise 'PE'
    # def resolve_option_type
    #   alert[:action].downcase == 'buy' ? 'CE' : 'PE'
    # end

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

    # def build_order_payload(trade_leg, derivative_instrument)
    #   {
    #     transactionType: trade_leg[:action],
    #     orderType: alert[:order_type].upcase,
    #     productType: Dhanhq::Constants::MARGIN,
    #     validity: Dhanhq::Constants::DAY,
    #     securityId: derivative_instrument.security_id,
    #     exchangeSegment: derivative_instrument.exchange_segment,
    #     quantity: calculate_quantity(trade_leg[:ltp], derivative_instrument.lot_size)
    #   }
    # end

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
