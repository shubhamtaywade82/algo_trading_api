# frozen_string_literal: true

module Option
  class StrategySuggester
    def initialize(option_chain, params)
      @option_chain = option_chain.with_indifferent_access
      @params = params
      @current_price = option_chain[:last_price].to_f
    end

    def suggest(criteria)
      strategies = Strategy.all
      strategies = apply_filters(strategies, criteria)

      affordable_strategies = strategies.select { |strategy| affordable?(strategy, criteria[:analysis]) }

      {
        index_details: index_details(criteria[:analysis]),
        strategies: affordable_strategies.map { |strategy| format_strategy(strategy, criteria[:analysis]) }
      }
    end

    private

    # Fetches available balance from Dhanhq::API::Funds.
    # Raises an error if the API call fails.
    #
    # @return [Float] The current available balance in the trading account.
    def available_balance
      @available_balance ||= Dhanhq::API::Funds.balance['availabelBalance'].to_f
    rescue StandardError
      raise 'Failed to fetch available balance'
    end

    def affordable?(strategy, analysis)
      strategy_example = send("generate_#{strategy.name.parameterize(separator: '_')}", analysis)

      return false if strategy_example.nil?

      strategy_cost = strategy_example.sum do |leg|
        leg[:max_loss].to_f
      rescue StandardError
        0.0
      end
      strategy_cost <= available_balance
    end

    def apply_filters(strategies, criteria)
      strategies = filter_by_outlook(strategies, criteria[:outlook]) if criteria[:outlook]
      strategies = filter_by_volatility(strategies, criteria[:volatility]) if criteria[:volatility]
      strategies = filter_by_risk(strategies, criteria[:risk]) if criteria[:risk]
      strategies
    end

    def format_strategy(strategy, analysis)
      {
        name: strategy.name,
        trade_legs: send("generate_#{strategy.name.parameterize(separator: '_')}", analysis),
        analysis: analysis
      }
    end

    def index_details(analysis)
      {
        ltp: @current_price,
        atm_strikes: atm_strikes.take(2),
        itm_strikes: itm_strikes.take(2),
        otm_strikes: otm_strikes.take(2),
        sentiment: analysis[:price_action_trends],
        key_levels: analysis[:support_resistance]
      }
    end

    def atm_strikes
      strikes_with_oi.select { |strike| (strike[:strike_price] - @current_price).abs <= 50 }
                     .sort_by { |strike| -strike[:oi] }
    end

    def itm_strikes
      strikes_with_oi.select { |strike| strike[:strike_price] < @current_price }
                     .sort_by { |strike| -strike[:oi] }
    end

    def otm_strikes
      strikes_with_oi.select { |strike| strike[:strike_price] > @current_price }
                     .sort_by { |strike| -strike[:oi] }
    end

    def strikes_with_oi
      @option_chain[:oc].map do |strike, data|
        {
          strike_price: strike.to_f,
          oi: (data.dig(:ce, :oi).to_i + data.dig(:pe, :oi).to_i),
          call_oi: data.dig(:ce, :oi).to_i,
          put_oi: data.dig(:pe, :oi).to_i
        }
      end
    end

    # **Trade Leg Structuring**

    # Individual strategy methods
    def generate_long_call(_analysis)
      call_option = best_option('ce')
      return unless call_option

      [{
        strike_price: call_option[:strike_price],
        option_type: 'CE',
        action: 'BUY',
        ltp: call_option[:last_price],
        max_loss: call_option[:last_price],
        max_profit: 'Unlimited',
        breakeven: call_option[:strike_price] + call_option[:last_price]
      }]
    end

    def generate_long_put(_analysis)
      put_option = best_option('pe')
      return unless put_option

      [{
        strike_price: put_option[:strike_price],
        option_type: 'PE',
        action: 'BUY',
        ltp: put_option[:last_price],
        max_loss: put_option[:last_price],
        max_profit: 'Substantial if price drops',
        breakeven: put_option[:strike_price] - put_option[:last_price]
      }]
    end

    def generate_long_straddle(_analysis)
      call_option = best_option('ce')
      put_option = best_option('pe')
      return unless call_option && put_option

      [
        {
          strike_price: call_option[:strike_price],
          option_type: 'CE',
          action: 'BUY',
          ltp: call_option[:last_price]
        },
        {
          strike_price: put_option[:strike_price],
          option_type: 'PE',
          action: 'BUY',
          ltp: put_option[:last_price]
        }
      ]
    end

    # **Long Strangle Strategy**
    def generate_long_strangle(_analysis)
      call_option = far_option('ce', 'OTM')
      put_option = far_option('pe', 'OTM')
      return unless call_option && put_option

      [
        { strike_price: call_option[:strike_price], option_type: 'CE', action: 'BUY', ltp: call_option[:last_price] },
        { strike_price: put_option[:strike_price], option_type: 'PE', action: 'BUY', ltp: put_option[:last_price] }
      ]
    end

    # **Long Butterfly Spread**
    def generate_long_butterfly_spread(_analysis)
      itm_option = far_option('pe', 'ITM')
      atm_option = best_option('pe')
      otm_option = far_option('pe', 'OTM')
      return unless itm_option && atm_option && otm_option

      [
        { strike_price: itm_option[:strike_price], option_type: 'PE', action: 'BUY', ltp: itm_option[:last_price] },
        { strike_price: atm_option[:strike_price], option_type: 'PE', action: 'SELL', ltp: atm_option[:last_price] },
        { strike_price: otm_option[:strike_price], option_type: 'PE', action: 'BUY', ltp: otm_option[:last_price] }
      ]
    end

    # **Long Calendar Spread**
    def generate_long_calendar_spread(_analysis)
      long_option = best_option('ce')
      short_option = far_option('ce', 'OTM')
      return unless long_option && short_option

      [
        { strike_price: long_option[:strike_price], option_type: 'CE', action: 'BUY', ltp: long_option[:last_price] },
        { strike_price: short_option[:strike_price], option_type: 'CE', action: 'SELL', ltp: short_option[:last_price] }
      ]
    end

    def generate_long_iron_condor(_analysis)
      call_buy = far_option('ce', 'OTM')
      put_buy = far_option('pe', 'OTM')
      call_sell = best_option('ce')
      put_sell = best_option('pe')
      return unless call_buy && put_buy && call_sell && put_sell

      [
        { strike_price: call_buy[:strike_price], option_type: 'CE', action: 'BUY', ltp: call_buy[:last_price] },
        { strike_price: put_buy[:strike_price], option_type: 'PE', action: 'BUY', ltp: put_buy[:last_price] },
        { strike_price: call_sell[:strike_price], option_type: 'CE', action: 'SELL', ltp: call_sell[:last_price] },
        { strike_price: put_sell[:strike_price], option_type: 'PE', action: 'SELL', ltp: put_sell[:last_price] }
      ]
    end

    # **Long Vega (Volatility Play)**
    def generate_long_vega_volatility_play(_analysis)
      otm_option = far_option('ce', 'OTM')
      return unless otm_option

      [
        { strike_price: otm_option[:strike_price], option_type: 'CE', action: 'BUY', ltp: otm_option[:last_price] }
      ]
    end

    # **Protective Long Put**
    def generate_protective_long_put(_analysis)
      put_option = best_option('pe')
      return unless put_option

      [
        { strike_price: put_option[:strike_price], option_type: 'PE', action: 'BUY', ltp: put_option[:last_price] }
      ]
    end

    # **Long Ratio Backspread**
    def generate_long_ratio_backspread(_analysis)
      otm_option_1 = far_option('ce', 'OTM')
      otm_option_2 = far_option('ce', 'OTM')
      itm_option = best_option('ce')
      return unless otm_option_1 && otm_option_2 && itm_option

      [
        { strike_price: otm_option_1[:strike_price], option_type: 'CE', action: 'BUY', ltp: otm_option_1[:last_price] },
        { strike_price: otm_option_2[:strike_price], option_type: 'CE', action: 'BUY', ltp: otm_option_2[:last_price] },
        { strike_price: itm_option[:strike_price], option_type: 'CE', action: 'SELL', ltp: itm_option[:last_price] }
      ]
    end

    # **Iron Butterfly**
    def generate_iron_butterfly(_analysis)
      call_sell = best_option('ce')
      put_sell = best_option('pe')
      call_buy = far_option('ce', 'OTM')
      put_buy = far_option('pe', 'OTM')
      return unless call_sell && put_sell && call_buy && put_buy

      [
        { strike_price: call_sell[:strike_price], option_type: 'CE', action: 'SELL', ltp: call_sell[:last_price] },
        { strike_price: put_sell[:strike_price], option_type: 'PE', action: 'SELL', ltp: put_sell[:last_price] },
        { strike_price: call_buy[:strike_price], option_type: 'CE', action: 'BUY', ltp: call_buy[:last_price] },
        { strike_price: put_buy[:strike_price], option_type: 'PE', action: 'BUY', ltp: put_buy[:last_price] }
      ]
    end

    # **Short Straddle**
    def generate_short_straddle(_analysis)
      call_option = best_option('ce')
      put_option = best_option('pe')
      return unless call_option && put_option

      [
        { strike_price: call_option[:strike_price], option_type: 'CE', action: 'SELL', ltp: call_option[:last_price] },
        { strike_price: put_option[:strike_price], option_type: 'PE', action: 'SELL', ltp: put_option[:last_price] }
      ]
    end

    # **Short Strangle**
    def generate_short_strangle(_analysis)
      call_option = far_option('ce', 'OTM')
      put_option = far_option('pe', 'OTM')
      return unless call_option && put_option

      [
        { strike_price: call_option[:strike_price], option_type: 'CE', action: 'SELL', ltp: call_option[:last_price] },
        { strike_price: put_option[:strike_price], option_type: 'PE', action: 'SELL', ltp: put_option[:last_price] }
      ]
    end

    def generate_bull_call_spread(_analysis)
      call_buy = best_option('ce')
      call_sell = far_option('ce', 'OTM')
      return unless call_buy && call_sell

      [
        {
          strike_price: call_buy[:strike_price],
          option_type: 'CE',
          action: 'BUY',
          ltp: call_buy[:last_price]
        },
        {
          strike_price: call_sell[:strike_price],
          option_type: 'CE',
          action: 'SELL',
          ltp: call_sell[:last_price]
        }
      ]
    end

    # **Bear Put Spread**
    def generate_bear_put_spread(_analysis)
      put_buy = best_option('pe')
      put_sell = far_option('pe', 'OTM')
      return unless put_buy && put_sell

      [
        { strike_price: put_buy[:strike_price], option_type: 'PE', action: 'BUY', ltp: put_buy[:last_price] },
        { strike_price: put_sell[:strike_price], option_type: 'PE', action: 'SELL', ltp: put_sell[:last_price] }
      ]
    end

    # Additional methods for other strategies can follow the same structure.

    def best_option(type)
      options = @option_chain[:oc].filter_map do |strike, data|
        next unless data[type]

        {
          strike_price: strike.to_f,
          last_price: data[type]['last_price'].to_f,
          symbol: "#{@params[:index_symbol]}-#{strike}-#{type.upcase}"
        }
      end
      options.min_by { |o| (o[:strike_price] - @current_price).abs }
    end

    def far_option(type, position)
      options = @option_chain[:oc].filter_map do |strike, data|
        next unless data[type]

        {
          strike_price: strike.to_f,
          last_price: data[type]['last_price'].to_f,
          symbol: "#{@params[:index_symbol]}-#{strike}-#{type.upcase}"
        }
      end

      case position
      when 'OTM'
        options.select { |o| o[:strike_price] > @current_price }.min_by { |o| o[:strike_price] - @current_price }
      when 'ITM'
        options.select { |o| o[:strike_price] < @current_price }.max_by { |o| o[:strike_price] }
      end
    end
  end
end
