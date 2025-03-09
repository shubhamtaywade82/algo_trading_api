# frozen_string_literal: true

module Option
  class ChainAnalyzer
    attr_reader :option_chain, :expiry, :underlying_spot, :historical_data

    # @param option_chain [Hash] => Real-time option chain from DhanHQ
    # @param expiry [String, Date] => The selected expiry date
    # @param underlying_spot [Float] => Current spot price of the underlying index
    # @param historical_data [Array<Hash>] => (Optional) historical candles for extended trend analysis
    def initialize(option_chain, expiry:, underlying_spot:, historical_data: [])
      @option_chain     = option_chain.with_indifferent_access
      @expiry           = expiry
      @underlying_spot  = underlying_spot.to_f
      @historical_data  = historical_data || []
    end

    # Perform a comprehensive analysis:
    # - Determine ATM strike
    # - Find best CE & PE strikes with advanced scoring (including previous_* changes)
    # - Summarize greeks across chain
    # - Analyze implied volatility
    # - Combine real-time & historical data to detect trend
    #
    # @return [Hash] The final analysis result
    def analyze
      {
        atm_strike: determine_atm_strike,
        best_ce_strike: best_strike_for(:ce),
        best_pe_strike: best_strike_for(:pe),
        trend: detect_trend,
        volatility: analyze_volatility,
        greeks_summary: summarize_greeks
      }
    end

    def analyze_for_stock_trading
      call_oi = sum_open_interest(:ce)
      put_oi = sum_open_interest(:pe)

      sentiment = if call_oi > put_oi * 1.5
                    'bullish'
                  elsif put_oi > call_oi * 1.5
                    'bearish'
                  else
                    'neutral'
                  end

      {
        support: find_high_oi_strike(:pe),
        resistance: find_high_oi_strike(:ce),
        sentiment: sentiment,
        volatility: analyze_volatility
      }
    end

    private

    def sum_open_interest(option_type)
      @option_chain[:oc].sum do |_, data|
        data.dig(option_type, 'oi').to_i
      end
    end

    def find_high_oi_strike(option_type)
      max_oi_strike = @option_chain[:oc].max_by do |_strike, data|
        data.dig(option_type, 'oi').to_i
      end

      max_oi_strike ? max_oi_strike.first.to_f : nil
    end

    ## (1) Determine ATM strike (closest to spot)
    def determine_atm_strike
      all_strikes = @option_chain[:oc]&.keys || []
      return nil if all_strikes.empty?

      float_strikes = all_strikes.map(&:to_f)
      float_strikes.min_by { |strike| (strike - @underlying_spot).abs }
    end

    ## (2) Score & pick best strike for CE or PE
    def best_strike_for(option_type)
      potential_strikes = gather_strikes(option_type)
      return nil if potential_strikes.empty?

      # Score each strike with an advanced formula that uses previous_* changes
      # Example: incorporate OI change & price change
      best = potential_strikes.max_by { |strike| scoring_formula(strike) }

      {
        strike_price: best[:strike_price],
        last_price: best[:last_price],
        oi: best[:oi],
        iv: best[:iv],
        greeks: best[:greeks],
        # Additional fields for momentum checks
        price_change: best[:price_change],
        oi_change: best[:oi_change],
        volume_change: best[:volume_change],
        previous_close: best[:previous_close_price],
        previous_oi: best[:previous_oi],
        previous_volume: best[:previous_volume]
      }
    end

    # Collect all relevant fields for each strike (CE or PE)
    def gather_strikes(option_type)
      return [] unless @option_chain[:oc]

      @option_chain[:oc].filter_map do |strike, data|
        next unless data[option_type]

        {
          strike_price: strike.to_f,
          last_price: data[option_type]['last_price'].to_f,
          oi: data[option_type]['oi'].to_i,
          iv: data[option_type]['implied_volatility'].to_f,
          greeks: {
            delta: data[option_type].dig('greeks', 'delta').to_f,
            gamma: data[option_type].dig('greeks', 'gamma').to_f,
            theta: data[option_type].dig('greeks', 'theta').to_f,
            vega: data[option_type].dig('greeks', 'vega').to_f
          },
          previous_close_price: data[option_type]['previous_close_price'].to_f,
          previous_oi: data[option_type]['previous_oi'].to_i,
          previous_volume: data[option_type]['previous_volume'].to_i,
          # Calculate changes from previous
          price_change: data[option_type]['last_price'].to_f - data[option_type]['previous_close_price'].to_f,
          oi_change: data[option_type]['oi'].to_i - data[option_type]['previous_oi'].to_i,
          volume_change: data[option_type]['volume'].to_i - data[option_type]['previous_volume'].to_i
        }
      end
    end

    # Example scoring formula that uses OI, IV, delta, and changes
    def scoring_formula(strike_data)
      # Ensure values are present and positive to prevent calculation issues
      oi             = strike_data[:oi].positive? ? strike_data[:oi] : 1.0
      volume         = strike_data[:volume_change].positive? ? strike_data[:volume_change] : 1.0
      iv             = strike_data[:iv].positive? ? strike_data[:iv] : 1.0
      price_change   = strike_data[:price_change] || 0
      delta_abs      = strike_data[:greeks][:delta].abs
      theta          = strike_data[:greeks][:theta] || 0
      vega           = strike_data[:greeks][:vega] || 0
      gamma          = strike_data[:greeks][:gamma] || 0
      top_bid_price  = strike_data[:top_bid_price] || 0
      top_ask_price  = strike_data[:top_ask_price] || 0
      bid_ask_spread = (top_ask_price - top_bid_price).abs || 0.1

      bid_ask_spread = 0.1 unless bid_ask_spread.positive?
      # **1. Liquidity Factor**
      liquidity_score = (oi * volume) / bid_ask_spread

      # **2. Momentum & Price Action Score**
      momentum_score = (price_change + (delta_abs * iv * 100))

      # **3. Sensitivity to Price Movement (Greeks Impact)**
      greeks_score = (delta_abs * 100) - (theta.abs * 5) + (vega * 2) + (gamma * 10)

      # **4. Final Weighted Score**
      (liquidity_score * 0.4) + (momentum_score * 0.3) + (greeks_score * 0.3)
    end

    ## (3) Summarize greeks across the entire chain
    def summarize_greeks
      all_strikes = @option_chain[:oc]&.values || []
      delta_vals = []
      gamma_vals = []
      theta_vals = []
      vega_vals = []

      all_strikes.each do |strike_data|
        %w[ce pe].each do |type|
          next unless strike_data[type]

          greeks_data = strike_data[type]['greeks'] || {}
          delta_vals << greeks_data['delta'].to_f  if greeks_data['delta']
          gamma_vals << greeks_data['gamma'].to_f  if greeks_data['gamma']
          theta_vals << greeks_data['theta'].to_f  if greeks_data['theta']
          vega_vals  << greeks_data['vega'].to_f   if greeks_data['vega']
        end
      end

      {
        delta: average(delta_vals),
        gamma: average(gamma_vals),
        theta: average(theta_vals),
        vega: average(vega_vals)
      }
    end

    ## (4) Analyze implied volatility across CE + PE
    def analyze_volatility
      all_values = []
      @option_chain[:oc]&.each_value do |data|
        ce_iv = data.dig(:ce, 'implied_volatility')
        pe_iv = data.dig(:pe, 'implied_volatility')
        all_values << ce_iv if ce_iv
        all_values << pe_iv if pe_iv
      end
      avg_iv = average(all_values)
      {
        average_iv: avg_iv,
        high_volatility: (avg_iv > 20) # or your chosen threshold
      }
    end

    ## (5) Detect Trend by combining chain-based price action & historical momentum
    def detect_trend
      chain_trend = analyze_price_action_from_chain
      hist_trend  = momentum_trend(@historical_data)

      return 'bullish' if chain_trend == 'bullish' && hist_trend == 'bullish'
      return 'bearish' if chain_trend == 'bearish' && hist_trend == 'bearish'

      'neutral'
    end

    # Simple chain-based approach -> short/long term average of CE prices
    def analyze_price_action_from_chain
      prices = @option_chain[:oc]&.values&.map { |data| data.dig('ce', 'last_price').to_f } || []
      return 'neutral' if prices.size < 5

      short_ma = moving_average(prices, 5).last
      long_ma  = moving_average(prices, 20).last || short_ma
      return 'bullish' if short_ma > long_ma
      return 'bearish' if short_ma < long_ma

      'neutral'
    end

    # Basic momentum from historical_data using 5 vs. 20 closes
    def momentum_trend(historical_data)
      return 'neutral' if historical_data.size < 20

      closes = historical_data.map { |row| row[:close].to_f }
      sma5 = closes.last(5).sum / 5
      sma20 = closes.last(20).sum / 20

      return 'bullish' if sma5 > sma20
      return 'bearish' if sma5 < sma20

      'neutral'
    end

    # Helpers
    def average(values)
      return 0.0 if values.empty?

      values.sum / values.size
    end

    def moving_average(data, period)
      # each_cons => consecutive subarrays
      data.each_cons(period).map { |slice| slice.sum / slice.size.to_f }
    end
  end
end
