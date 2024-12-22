module Option
  class StrategySuggester
    def initialize(option_chain, params)
      @option_chain = option_chain.with_indifferent_access
      @params = params
      @current_price = @option_chain.dig(:data, :last_price) || 0
    end

    def suggest
      Strategy.all.map do |strategy|
        strategy.as_json.merge(
          example: generate_example(strategy.name)
        )
      end
    end

    private

    def generate_example(name)
      case name
      when "Long Call"
        option = best_option("ce")
        format_example("Buy #{option[:symbol]} @ ₹#{option[:last_price]}") if option
      when "Long Put"
        option = best_option("pe")
        format_example("Buy #{option[:symbol]} @ ₹#{option[:last_price]}") if option
      when "Long Straddle"
        call_option = best_option("ce")
        put_option = best_option("pe")
        if call_option && put_option
          format_example("Buy #{call_option[:symbol]} and #{put_option[:symbol]} @ ₹#{call_option[:last_price]} + ₹#{put_option[:last_price]}")
        end
      when "Long Strangle"
        call_option = far_option("ce", "OTM")
        put_option = far_option("pe", "OTM")
        if call_option && put_option
          format_example("Buy #{call_option[:symbol]} and #{put_option[:symbol]} @ ₹#{call_option[:last_price]} + ₹#{put_option[:last_price]}")
        end
      else
        { note: "No example available for this strategy." }
      end
    end

    def best_option(type)
      options = @option_chain.dig(:data, :oc).select do |strike, data|
        data[type].present?
      end

      options.map do |strike, data|
        {
          strike_price: strike.to_f,
          last_price: data[type][:last_price],
          symbol: "#{@params[:index_symbol]}-#{strike}-#{type.upcase}"
        }
      end.min_by { |o| (o[:strike_price] - @current_price).abs }
    end

    def far_option(type, position)
      options = @option_chain.dig(:data, :oc).select do |strike, data|
        data[type].present?
      end

      mapped_options = options.map do |strike, data|
        {
          strike_price: strike.to_f,
          last_price: data[type][:last_price],
          symbol: "#{@params[:index_symbol]}-#{strike}-#{type.upcase}"
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
      { action: action, max_loss: "Premium Paid", max_profit: "Unlimited (in most cases)" }
    end
  end
end
