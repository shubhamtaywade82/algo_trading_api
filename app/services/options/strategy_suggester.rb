module Options
  class StrategySuggester
    def initialize(analysis, params)
      @analysis = analysis
      @params = params
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
        option = best_option("CE")
        format_example("Buy #{option[:symbol]} @ ₹#{option[:last_price]}")
      when "Long Put"
        option = best_option("PE")
        format_example("Buy #{option[:symbol]} @ ₹#{option[:last_price]}")
      # Add examples for all strategies here...
      else
        { note: "No example available for this strategy." }
      end
    end

    def best_option(type)
      options = @analysis[:options].select { |o| o[:type] == type }
      options.min_by { |o| (o[:strike_price] - @analysis[:current_price]).abs }
    end

    def format_example(action)
      { action: action, max_loss: "Premium Paid", max_profit: "Unlimited (in most cases)" }
    end
  end
end
