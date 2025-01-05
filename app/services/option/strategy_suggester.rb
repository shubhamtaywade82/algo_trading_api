module Option
  class StrategySuggester
    def initialize(option_chain, params)
      @option_chain = option_chain.with_indifferent_access
      @params = params
      @current_price = option_chain.dig(:last_price).to_f
    end

    def suggest(criteria)
      strategies = Strategy.all
      strategies = apply_filters(strategies, criteria)
      pp strategies
      strategies.map { |strategy| format_strategy(strategy, criteria[:analysis]) }
    end

    private

    def apply_filters(strategies, criteria)
      strategies = filter_by_outlook(strategies, criteria[:outlook]) if criteria[:outlook]
      strategies = filter_by_volatility(strategies, criteria[:volatility]) if criteria[:volatility]
      strategies = filter_by_risk(strategies, criteria[:risk]) if criteria[:risk]
      strategies
    end

    def format_strategy(strategy, analysis)
      {
        name: strategy.name,
        example: send("generate_#{strategy.name.parameterize(separator: '_')}", analysis),
        analysis: analysis
      }
    end

    # Individual strategy methods
    def generate_long_call(_analysis)
      call_option = best_option("ce")
      return unless call_option

      {
        action: "Buy #{call_option[:symbol]} @ ₹#{call_option[:last_price]}",
        max_loss: call_option[:last_price],
        max_profit: "Unlimited (depending on price rise)",
        breakeven: call_option[:strike_price] + call_option[:last_price]
      }
    end

    def generate_long_put(_analysis)
      put_option = best_option("pe")
      return unless put_option

      {
        action: "Buy #{put_option[:symbol]} @ ₹#{put_option[:last_price]}",
        max_loss: put_option[:last_price],
        max_profit: "Substantial if the price drops sharply",
        breakeven: put_option[:strike_price] - put_option[:last_price]
      }
    end

    def generate_long_straddle(_analysis)
      call_option = best_option("ce")
      put_option = best_option("pe")
      return unless call_option && put_option

      {
        action: "Buy #{call_option[:symbol]} @ ₹#{call_option[:last_price]} and #{put_option[:symbol]} @ ₹#{put_option[:last_price]}",
        max_loss: call_option[:last_price] + put_option[:last_price],
        max_profit: "Unlimited if price moves significantly in either direction",
        breakeven: [
          @current_price - (call_option[:last_price] + put_option[:last_price]),
          @current_price + (call_option[:last_price] + put_option[:last_price])
        ]
      }
    end

    def generate_long_strangle(_analysis)
      call_option = far_option("ce", "OTM")
      put_option = far_option("pe", "OTM")
      return unless call_option && put_option

      {
        action: "Buy #{call_option[:symbol]} @ ₹#{call_option[:last_price]} and #{put_option[:symbol]} @ ₹#{put_option[:last_price]}",
        max_loss: call_option[:last_price] + put_option[:last_price],
        max_profit: "Unlimited if price moves sharply in either direction",
        breakeven: [
          put_option[:strike_price] - call_option[:last_price],
          call_option[:strike_price] + put_option[:last_price]
        ]
      }
    end

    def generate_long_butterfly_spread(_analysis)
      itm_option = far_option("pe", "ITM")
      atm_option = best_option("pe")
      otm_option = far_option("pe", "OTM")
      return unless itm_option && atm_option && otm_option

      {
        action: "Buy #{itm_option[:symbol]} and #{otm_option[:symbol]}, Sell #{atm_option[:symbol]}",
        max_loss: "Net premium paid",
        max_profit: "Limited but occurs if price stays near the middle strike",
        breakeven: [
          itm_option[:strike_price] - (atm_option[:last_price] + otm_option[:last_price]),
          otm_option[:strike_price] + (atm_option[:last_price] + otm_option[:last_price])
        ]
      }
    end

    def generate_long_calendar_spread(_analysis)
      long_option = best_option("ce")
      short_option = far_option("ce", "OTM")
      return unless long_option && short_option

      {
        action: "Buy #{long_option[:symbol]} (long-dated) and Sell #{short_option[:symbol]} (near-dated)",
        max_loss: long_option[:last_price] - short_option[:last_price],
        max_profit: "Moderate if price moves in anticipated direction slowly",
        breakeven: "Depends on time decay differences"
      }
    end

    def generate_long_iron_condor(_analysis)
      call_buy = far_option("ce", "OTM")
      put_buy = far_option("pe", "OTM")
      call_sell = best_option("ce")
      put_sell = best_option("pe")
      return unless call_buy && put_buy && call_sell && put_sell

      {
        action: "Buy #{call_buy[:symbol]} and #{put_buy[:symbol]}, Sell #{call_sell[:symbol]} and #{put_sell[:symbol]}",
        max_loss: (call_buy[:last_price] + put_buy[:last_price]) - (call_sell[:last_price] + put_sell[:last_price]),
        max_profit: (call_sell[:last_price] + put_sell[:last_price]) - (call_buy[:last_price] + put_buy[:last_price]),
        breakeven: [
          call_sell[:strike_price] - (call_sell[:last_price] + put_sell[:last_price]),
          put_sell[:strike_price] + (call_sell[:last_price] + put_sell[:last_price])
        ]
      }
    end

    def generate_long_vega_volatility_play(_analysis)
      otm_option = far_option("ce", "OTM")
      return unless otm_option

      {
        action: "Buy #{otm_option[:symbol]} @ ₹#{otm_option[:last_price]}",
        max_loss: otm_option[:last_price],
        max_profit: "Depends on IV increase before significant movement",
        breakeven: "Depends on volatility shift"
      }
    end

    def generate_protective_long_put(_analysis)
      put_option = best_option("pe")
      return unless put_option

      {
        action: "Buy #{put_option[:symbol]} @ ₹#{put_option[:last_price]} to hedge",
        max_loss: put_option[:last_price],
        max_profit: "Unlimited (depending on downside risk)",
        breakeven: put_option[:strike_price] - put_option[:last_price]
      }
    end

    def generate_long_ratio_backspread(_analysis)
      otm_option_1 = far_option("ce", "OTM")
      otm_option_2 = far_option("ce", "OTM")
      itm_option = best_option("ce")
      return unless otm_option_1 && otm_option_2 && itm_option

      {
        action: "Buy 2 #{otm_option_1[:symbol]} and Sell 1 #{itm_option[:symbol]}",
        max_loss: itm_option[:last_price] - (otm_option_1[:last_price] * 2),
        max_profit: "High if price moves significantly in expected direction",
        breakeven: "Depends on sharp price movements"
      }
    end

    def generate_iron_butterfly(_analysis)
      call_sell = best_option("ce")
      put_sell = best_option("pe")
      call_buy = far_option("ce", "OTM")
      put_buy = far_option("pe", "OTM")
      return unless call_sell && put_sell && call_buy && put_buy

      {
        action: "Sell #{call_sell[:symbol]} and #{put_sell[:symbol]}, Buy #{call_buy[:symbol]} and #{put_buy[:symbol]}",
        max_loss: (call_buy[:last_price] + put_buy[:last_price]) - (call_sell[:last_price] + put_sell[:last_price]),
        max_profit: (call_sell[:last_price] + put_sell[:last_price]) - (call_buy[:last_price] + put_buy[:last_price]),
        breakeven: [
          call_sell[:strike_price] - (call_sell[:last_price] + put_sell[:last_price]),
          put_sell[:strike_price] + (call_sell[:last_price] + put_sell[:last_price])
        ]
      }
    end

    def generate_short_straddle(_analysis)
      call_option = best_option("ce")
      put_option = best_option("pe")
      return { error: "Required options not found" } unless call_option && put_option

      {
        action: "Sell #{call_option[:symbol]} @ ₹#{call_option[:last_price]} and Sell #{put_option[:symbol]} @ ₹#{put_option[:last_price]}",
        max_loss: "Unlimited (if the price moves significantly in either direction)",
        max_profit: call_option[:last_price] + put_option[:last_price],
        breakeven: [
          @current_price - (call_option[:last_price] + put_option[:last_price]),
          @current_price + (call_option[:last_price] + put_option[:last_price])
        ]
      }
    end

    def generate_short_strangle(_analysis)
      call_option = far_option("ce", "OTM")
      put_option = far_option("pe", "OTM")
      return { error: "Required options not found" } unless call_option && put_option

      {
        action: "Sell #{call_option[:symbol]} @ ₹#{call_option[:last_price]} and Sell #{put_option[:symbol]} @ ₹#{put_option[:last_price]}",
        max_loss: "Unlimited (if price moves significantly beyond OTM strikes)",
        max_profit: call_option[:last_price] + put_option[:last_price],
        breakeven: [
          put_option[:strike_price] - (call_option[:last_price] + put_option[:last_price]),
          call_option[:strike_price] + (call_option[:last_price] + put_option[:last_price])
        ]
      }
    end

    def generate_bull_call_spread(_analysis)
      call_buy = best_option("ce") # Closest strike price to the current price
      call_sell = far_option("ce", "OTM") # OTM option for the spread

      return { error: "Required options not found for Bull Call Spread strategy" } unless call_buy && call_sell

      {
        action: "Buy #{call_buy[:symbol]} @ ₹#{call_buy[:last_price]} and Sell #{call_sell[:symbol]} @ ₹#{call_sell[:last_price]}",
        max_loss: call_buy[:last_price] - call_sell[:last_price],
        max_profit: (call_sell[:strike_price] - call_buy[:strike_price]) - (call_buy[:last_price] - call_sell[:last_price]),
        breakeven: call_buy[:strike_price] + (call_buy[:last_price] - call_sell[:last_price])
      }
    end

    def generate_bear_put_spread(_analysis)
      put_buy = best_option("pe") # Closest strike price to the current price
      put_sell = far_option("pe", "OTM") # OTM option for the spread

      return { error: "Required options not found for Bear Put Spread strategy" } unless put_buy && put_sell

      {
        action: "Buy #{put_buy[:symbol]} @ ₹#{put_buy[:last_price]} and Sell #{put_sell[:symbol]} @ ₹#{put_sell[:last_price]}",
        max_loss: put_buy[:last_price] - put_sell[:last_price],
        max_profit: (put_buy[:strike_price] - put_sell[:strike_price]) - (put_buy[:last_price] - put_sell[:last_price]),
        breakeven: put_buy[:strike_price] - (put_buy[:last_price] - put_sell[:last_price])
      }
    end

    # Additional methods for other strategies can follow the same structure.

    def best_option(type)
      options = @option_chain[:oc].map do |strike, data|
        next unless data[type]
        {
          strike_price: strike.to_f,
          last_price: data[type]["last_price"].to_f,
          symbol: "#{@params[:index_symbol]}-#{strike}-#{type.upcase}"
        }
      end.compact
      options.min_by { |o| (o[:strike_price] - @current_price).abs }
    end

    def far_option(type, position)
      options = @option_chain[:oc].map do |strike, data|
        next unless data[type]
        {
          strike_price: strike.to_f,
          last_price: data[type]["last_price"].to_f,
          symbol: "#{@params[:index_symbol]}-#{strike}-#{type.upcase}"
        }
      end.compact

      case position
      when "OTM"
        options.select { |o| o[:strike_price] > @current_price }.min_by { |o| o[:strike_price] - @current_price }
      when "ITM"
        options.select { |o| o[:strike_price] < @current_price }.max_by { |o| o[:strike_price] }
      end
    end
  end
end
