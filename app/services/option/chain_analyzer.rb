# frozen_string_literal: true

module Option
  class ChainAnalyzer
    attr_reader :options_chain

    def initialize(options_chain)
      @options_chain = options_chain.with_indifferent_access
    end

    def analyze
      {
        max_pain: calculate_max_pain,
        support_resistance: analyze_support_resistance,
        greeks_summary: analyze_greeks,
        volatility_trends: analyze_volatility,
        price_action_trends: analyze_price_action
      }
    end

    private

    def calculate_max_pain
      strikes = @options_chain[:oc].keys
      strikes.map do |strike|
        oi_call = @options_chain.dig(:oc, strike, :ce, :oi).to_i
        oi_put = @options_chain.dig(:oc, strike, :pe, :oi).to_i
        [strike.to_f, oi_call + oi_put]
      end.min_by { |_strike, combined_oi| combined_oi }&.first
    end

    def analyze_support_resistance
      calls = fetch_oi_data(:ce)
      pe = fetch_oi_data(:pe)

      {
        resistance: calls.max_by { |c| c[:oi] }&.dig(:strike),
        support: pe.max_by { |p| p[:oi] }&.dig(:strike)
      }
    end

    def analyze_greeks
      %w[delta gamma theta vega].each_with_object({}) do |greek, summary|
        values = collect_greek_values(greek)

        summary[greek] = average(values) if values.any?
      end
    end

    def analyze_volatility
      iv_data = collect_iv_data
      {
        average_iv: average(iv_data),
        iv_trend: trend(iv_data)
      }
    end

    def analyze_price_action
      prices = @options_chain[:oc]&.values&.map { |data| data.dig('ce', 'last_price').to_f } || []

      return { bullish: false, bearish: false, neutral: true } if prices.empty? || prices.size < 5

      # Moving Averages
      short_term_ma = moving_average(prices, 5)
      long_term_ma = moving_average(prices, 20)

      {
        bullish: short_term_ma.last > long_term_ma.last,
        bearish: short_term_ma.last < long_term_ma.last,
        neutral: short_term_ma.last == long_term_ma.last
      }
    end

    def fetch_oi_data(type)
      @options_chain[:oc].filter_map do |strike, data|
        { strike: strike.to_f, oi: data.dig(type, :oi).to_i } if data[type]
      end
    end

    def collect_greek_values(greek)
      @options_chain[:oc].values.flat_map do |data|
        [data.dig(:ce, :greeks, greek), data.dig(:pe, :greeks, greek)].compact
      end
    end

    def collect_iv_data
      @options_chain[:oc].values.flat_map do |data|
        [data.dig(:ce, :implied_volatility), data.dig(:pe, :implied_volatility)].compact
      end
    end

    def average(values)
      values.sum / values.size
    end

    def trend(values)
      return 'neutral' if values.empty? || values.size < 2

      values.last > values.first ? 'increasing' : 'decreasing'
    end

    def bullish_trend?(prices, volumes)
      moving_average(prices, 5).last > moving_average(prices, 20).last && increasing?(volumes)
    end

    def bearish_trend?(prices, volumes)
      moving_average(prices, 5).last < moving_average(prices, 20).last && decreasing?(volumes)
    end

    def moving_average(data, period)
      data.each_cons(period).map { |slice| slice.sum / slice.size.to_f }
    end

    def increasing?(data)
      data.each_cons(2).all? { |a, b| b >= a }
    end

    def decreasing?(data)
      data.each_cons(2).all? { |a, b| b <= a }
    end
  end
end
