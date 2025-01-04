module Option
  class ChainAnalyzer
    def initialize(options_chain)
      @options_chain = options_chain.with_indifferent_access
    end

    def analyze
      {
        max_pain: calculate_max_pain,
        oi_support_resistance: analyze_oi_support_resistance,
        greeks_summary: analyze_greeks,
        price_action_trends: analyze_price_action
      }
    end

    private

    def calculate_max_pain
      strikes = @options_chain.dig(:oc).keys
      strikes.map do |strike|
        oi_call = @options_chain.dig(:oc, strike, "ce", :open_interest).to_i
        oi_put = @options_chain.dig(:oc, strike, "pe", :open_interest).to_i
        [ strike, oi_call + oi_put ]
      end.min_by { |_strike, combined_oi| combined_oi }&.first
    end

    def analyze_oi_support_resistance
      calls = @options_chain.dig(:oc).filter_map do |strike, data|
        { strike: strike.to_f, oi: data.dig("ce", :open_interest).to_i } if data["ce"]
      end
      pe = @options_chain.dig(:oc).filter_map do |strike, data|
        { strike: strike.to_f, oi: data.dig("pe", :open_interest).to_i } if data["pe"]
      end

      {
        resistance: calls.max_by { |c| c[:oi] }&.dig(:strike),
        support: pe.max_by { |p| p[:oi] }&.dig(:strike)
      }
    end

    def analyze_greeks
      greeks = %w[delta gamma theta vega].each_with_object({}) do |greek, summary|
        values = @options_chain.dig(:oc).values.flat_map do |data|
          [ data.dig("ce", greek), data.dig("pe", greek) ].compact
        end
        summary[:"#{greek}_avg"] = values.sum / values.size if values.any?
      end

      greeks
    end

    def analyze_price_action
      prices = @options_chain.dig(:prices) || [] # Assume price data is available in the options chain
      volumes = @options_chain.dig(:volumes) || [] # Assume volume data is available

      return { bullish: false, bearish: false, neutral: true } if prices.empty? || prices.size < 5

      # Calculate Moving Averages
      short_term_ma = moving_average(prices, 5) # 5-period MA
      long_term_ma = moving_average(prices, 20) # 20-period MA

      # Determine Trends
      bullish = short_term_ma.last > long_term_ma.last && increasing(prices) && increasing(volumes)
      bearish = short_term_ma.last < long_term_ma.last && decreasing(prices) && decreasing(volumes)
      neutral = !bullish && !bearish

      { bullish: bullish, bearish: bearish, neutral: neutral }
    end

    private

    def moving_average(data, period)
      return [] if data.size < period
      data.each_cons(period).map { |sub_array| sub_array.sum / period.to_f }
    end

    def increasing(data)
      data.each_cons(2).all? { |a, b| b >= a }
    end

    def decreasing(data)
      data.each_cons(2).all? { |a, b| b <= a }
    end
  end
end
