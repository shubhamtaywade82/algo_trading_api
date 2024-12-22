module Option
  class StrategySuggester
    def initialize(option_chain, params)
      @option_chain = option_chain.with_indifferent_access
      @params = params
      @current_price = @option_chain.dig(:data, :last_price) || 0
    end

    def suggest(criteria = {})
      strategies = Strategy.all

      # Filter strategies based on market outlook
      if criteria[:outlook] == "bullish"
        strategies = strategies.where(name: [ "Long Call", "Bull Call Spread", "Long Ratio Backspread", "Protective Long Put" ])
      elsif criteria[:outlook] == "bearish"
        strategies = strategies.where(name: [ "Long Put", "Bear Put Spread", "Short Straddle", "Short Strangle" ])
      end

      # Filter strategies based on volatility expectations
      if criteria[:volatility] == "high"
        strategies = strategies.where(name: [ "Long Straddle", "Long Strangle", "Iron Butterfly", "Long Vega (Volatility Play)" ])
      elsif criteria[:volatility] == "low"
        strategies = strategies.where(name: [ "Short Straddle", "Short Strangle", "Iron Condor", "Iron Butterfly" ])
      end

      # Filter based on risk preference (low, moderate, high)
      if criteria[:risk] == "low"
        strategies = strategies.where(name: [ "Iron Condor", "Iron Butterfly", "Protective Long Put" ])
      elsif criteria[:risk] == "moderate"
        strategies = strategies.where(name: [ "Bull Call Spread", "Bear Put Spread", "Long Calendar Spread", "Long Ratio Backspread" ])
      elsif criteria[:risk] == "high"
        strategies = strategies.where(name: [ "Long Call", "Long Put", "Long Straddle", "Long Strangle" ])
      end

      # Filter strategies based on option preference (buy, sell, or both)
      case criteria[:option_preference]
      when "buy"
        strategies = strategies.where(name: ["Long Call", "Long Put", "Long Straddle", "Long Strangle", "Bull Call Spread", "Bear Put Spread", "Protective Long Put", "Long Vega (Volatility Play)"])
      when "sell"
        strategies = strategies.where(name: ["Short Straddle", "Short Strangle", "Iron Condor", "Iron Butterfly"])
      end

      # Map filtered strategies with generated examples
      strategies.map do |strategy|
        strategy.as_json.merge(
          example: generate_example(strategy.name)
        )
      end
    end

    def generate_example(name)
      case name
      when "Bull Call Spread"
        call_buy = best_option("ce")
        call_sell = far_option("ce", "OTM")
        if call_buy && call_sell
          format_example("Buy #{call_buy[:symbol]} and Sell #{call_sell[:symbol]} @ ₹#{call_buy[:last_price]} - ₹#{call_sell[:last_price]}")
        end
      when "Bear Put Spread"
        put_buy = best_option("pe")
        put_sell = far_option("pe", "OTM")
        if put_buy && put_sell
          format_example("Buy #{put_buy[:symbol]} and Sell #{put_sell[:symbol]} @ ₹#{put_buy[:last_price]} - ₹#{put_sell[:last_price]}")
        end
      when "Short Straddle"
        call_option = best_option("ce")
        put_option = best_option("pe")
        if call_option && put_option
          format_example("Sell #{call_option[:symbol]} and Sell #{put_option[:symbol]} @ ₹#{call_option[:last_price]} + ₹#{put_option[:last_price]}")
        end
      when "Short Strangle"
        call_option = far_option("ce", "OTM")
        put_option = far_option("pe", "OTM")
        if call_option && put_option
          format_example("Sell #{call_option[:symbol]} and Sell #{put_option[:symbol]} @ ₹#{call_option[:last_price]} + ₹#{put_option[:last_price]}")
        end
      when "Protective Long Put"
        put_option = best_option("pe")
        if put_option
          format_example("Buy #{put_option[:symbol]} to hedge a long position @ ₹#{put_option[:last_price]}")
        end
      when "Iron Butterfly"
        call_sell = best_option("ce")
        put_sell = best_option("pe")
        call_buy = far_option("ce", "OTM")
        put_buy = far_option("pe", "OTM")
        if call_sell && put_sell && call_buy && put_buy
          format_example("Sell #{call_sell[:symbol]}, Sell #{put_sell[:symbol]}, Buy #{call_buy[:symbol]}, Buy #{put_buy[:symbol]}")
        end
      when "Iron Condor"
        call_sell = far_option("ce", "OTM")
        put_sell = far_option("pe", "OTM")
        call_buy = far_option("ce", "OTM")
        put_buy = far_option("pe", "OTM")
        if call_sell && put_sell && call_buy && put_buy
          format_example("Sell #{call_sell[:symbol]}, Sell #{put_sell[:symbol]}, Buy #{call_buy[:symbol]}, Buy #{put_buy[:symbol]} @ ₹#{call_sell[:last_price]} + ₹#{put_sell[:last_price]} - ₹#{call_buy[:last_price]} - ₹#{put_buy[:last_price]}")
        end
      when "Long Calendar Spread"
        long_option = best_option("ce")
        short_option = best_option("ce")
        if long_option && short_option
          format_example("Buy #{long_option[:symbol]} (Jan expiry) and Sell #{short_option[:symbol]} (Dec expiry) @ ₹#{long_option[:last_price]} - ₹#{short_option[:last_price]}")
        end
      else
        strategy = Strategy.find_by(name: name)
        strategy&.example || { note: "No dynamic example available for this strategy." }
      end
    end

    private

    def update_examples
      Strategy.all.each do |strategy|
        example = generate_example(strategy.name)
        strategy.update(example: example) if example.is_a?(String)
      end
    end

    def best_option(type)
      options = @option_chain.dig(:data, :oc).select do |strike, data|
        data[type].present?
      end

      return nil if options.empty?

      options.map do |strike, data|
        {
          strike_price: strike.to_f,
          last_price: data[type][:last_price],
          symbol: "#{@params[:index_symbol]}-#{strike.to_i}-#{type.upcase}"
        }
      end.min_by { |o| (o[:strike_price] - @current_price).abs }
    end

    def far_option(type, position)
      options = @option_chain.dig(:data, :oc).select do |strike, data|
        data[type].present?
      end

      return nil if options.empty?

      mapped_options = options.map do |strike, data|
        {
          strike_price: strike.to_f,
          last_price: data[type][:last_price],
          symbol: "#{@params[:index_symbol]}-#{strike.to_i}-#{type.upcase}"
        }
      end

      case position
      when "OTM"
        mapped_options.select { |o| o[:strike_price] > @current_price }.min_by { |o| o[:strike_price] - @current_price }
      when "ITM"
        mapped_options.select { |o| o[:strike_price] < @current_price }.max_by { |o| o[:strike_price] }
      else
        nil
      end
    end

    def format_example(action)
      {
        action: action,
        max_loss: "Premium Paid",
        max_profit: "Unlimited (in most cases)",
        note: "Example generated dynamically based on the current option chain."
      }
    end
  end
end
