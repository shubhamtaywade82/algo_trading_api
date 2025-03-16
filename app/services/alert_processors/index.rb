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

      # 4) Build ChainAnalyzer with new parameters
      chain_analyzer = Option::ChainAnalyzer.new(
        option_chain,
        expiry: expiry,
        underlying_spot: option_chain[:last_price] || ltp,
        historical_data: fetch_historical_data
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
      alert[:strategy_type] == 'intraday' ? fetch_intraday_candles : fetch_short_historical_data
    end

    # Example: fetch 5 days of daily candles
    def fetch_short_historical_data
      Dhanhq::API::Historical.daily(
        securityId: instrument.security_id,
        exchangeSegment: instrument.exchange_segment,
        instrument: instrument.instrument_type,
        fromDate: 45.days.ago.to_date.to_s,
        toDate: Date.yesterday.to_s
      )
    rescue StandardError
      []
    end

    def fetch_intraday_candles
      Dhanhq::API::Historical.intraday(
        securityId: instrument.security_id,
        exchangeSegment: instrument.exchange_segment,
        instrument: instrument.instrument_type,
        interval: '5', # 5-min bars
        fromDate: 5.days.ago.to_date.to_s,
        toDate: Time.zone.today.to_s
      )
    rescue StandardError => e
      Rails.logger.error("Failed to fetch intraday data => #{e.message}")
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
      action = 'BUY' || alert[:action].to_s.upcase # 'BUY' or 'SELL'
      quantity = calculate_quantity(best_strike[:last_price], derivative_instrument.lot_size)
      Rails.logger.debug quantity
      {
        transactionType: action,
        orderType: alert[:order_type].to_s.upcase,
        productType: Dhanhq::Constants::MARGIN,
        validity: Dhanhq::Constants::DAY,
        securityId: derivative_instrument.security_id,
        exchangeSegment: derivative_instrument.exchange_segment,
        quantity: quantity
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
      available_balance = fetch_available_balance
      required_margin = price * lot_size

      # 1. Use 50% of the available_balance, or adapt the fraction if you want.
      adjusted_alloc_qty = buyable_lots(available_balance, 0.5, price, lot_size)
      return adjusted_alloc_qty if adjusted_alloc_qty >= lot_size

      # 2. If half was too small, let’s try the entire available_balance
      adjusted_qty = buyable_lots(available_balance, 1.0, price, lot_size)
      return adjusted_qty if adjusted_qty >= lot_size

      # 3) Insufficient to buy even 1 lot:
      raise "Insufficient funds to buy at least 1 lot. Price=#{price}, lot_size=#{lot_size}, " \
            "available_balance=#{available_balance}, trade margin=#{required_margin}, required_balance=#{required_margin - available_balance}"
    end

    # Calculates how many total units we can buy if we allocate
    # `fraction` of `balance`, at a given `price`.
    # Then we snap that down to a multiple of `lot_size`.
    #
    # @param balance [Numeric] Total account balance
    # @param fraction [Numeric] 0.5 => 50% of account; 1.0 => 100%; etc.
    # @param price [Numeric] Price per contract
    # @param lot_size [Integer] Contract lot size
    # @return [Integer] The maximum quantity aligned to lot size
    def buyable_lots(balance, fraction, price, lot_size)
      allocation     = balance * fraction
      max_whole_qty  = (allocation / price).floor
      (max_whole_qty / lot_size) * lot_size
    end
  end
end
