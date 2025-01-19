# frozen_string_literal: true

class NiftyTradeService
  def initialize(levels)
    @levels = levels
  end

  def execute_trade
    nifty_ltp = fetch_ltp
    option_chain = fetch_option_chain

    if nifty_ltp <= @levels[:demand_zone]
      handle_demand_zone_trade(nifty_ltp, option_chain)
    elsif nifty_ltp >= @levels[:supply_zone]
      handle_supply_zone_trade(nifty_ltp, option_chain)
    else
      Rails.logger.debug { "Nifty is trading within the range. No trade executed. LTP: #{nifty_ltp}" }
    end
  end

  private

  def fetch_ltp
    response = Dhanhq::API::MarketFeed.ltp({
                                             'NSE_EQ' => [1333] # Replace with Nifty index security ID
                                           })

    raise "Error fetching LTP: #{response['error']}" unless response['status'] == 'success'

    response['data']['NSE_EQ']['1333']['last_price']
  end

  def fetch_option_chain
    response = Dhanhq::API::Option.chain({
                                           UnderlyingScrip: 1333, # Replace with Nifty index security ID
                                           UnderlyingSeg: 'NSE_FNO',
                                           Expiry: nearest_expiry_date
                                         })

    raise "Error fetching Option Chain: #{response['error']}" unless response['status'] == 'success'

    response['data']
  end

  def handle_demand_zone_trade(ltp, option_chain)
    Rails.logger.debug { "Nifty near demand zone. LTP: #{ltp}, Demand Zone: #{@levels[:demand_zone]}" }

    # Analyze option chain for strike price near the demand zone
    strike_to_buy = find_strike_near_zone(option_chain, @levels[:demand_zone], :call)

    # Place a call option buy order
    Dhanhq::API::Orders.place({
                                securityId: strike_to_buy[:security_id],
                                transactionType: 'BUY',
                                exchangeSegment: 'NSE_FNO',
                                productType: 'INTRADAY',
                                orderType: 'MARKET',
                                quantity: 75, # Nifty lot size
                                price: nil,
                                drvOptionType: 'CALL',
                                drvStrikePrice: strike_to_buy[:strike]
                              })

    Rails.logger.debug { "Bought CALL option at strike: #{strike_to_buy[:strike]}" }
  end

  def handle_supply_zone_trade(ltp, option_chain)
    Rails.logger.debug { "Nifty near supply zone. LTP: #{ltp}, Supply Zone: #{@levels[:supply_zone]}" }

    # Analyze option chain for strike price near the supply zone
    strike_to_buy = find_strike_near_zone(option_chain, @levels[:supply_zone], :put)

    # Place a put option buy order
    Dhanhq::API::Orders.place({
                                securityId: strike_to_buy[:security_id],
                                transactionType: 'BUY',
                                exchangeSegment: 'NSE_FNO',
                                productType: 'INTRADAY',
                                orderType: 'MARKET',
                                quantity: 75, # Nifty lot size
                                price: nil,
                                drvOptionType: 'PUT',
                                drvStrikePrice: strike_to_buy[:strike]
                              })

    Rails.logger.debug { "Bought PUT option at strike: #{strike_to_buy[:strike]}" }
  end

  def find_strike_near_zone(option_chain, zone, option_type)
    strikes = option_chain['strikes']
    valid_strikes = strikes.select do |strike|
      option_type == :call ? strike['strikePrice'] >= zone : strike['strikePrice'] <= zone
    end

    valid_strikes.min_by { |strike| (strike['strikePrice'] - zone).abs }
  end

  def nearest_expiry_date
    # Fetch nearest expiry date dynamically
    response = Dhanhq::API::Option.expiry_list({
                                                 UnderlyingScrip: 1333,
                                                 UnderlyingSeg: 'NSE_FNO'
                                               })

    raise "Error fetching expiry dates: #{response['error']}" unless response['status'] == 'success'

    response['data']['expiryDates'].first
  end
end
