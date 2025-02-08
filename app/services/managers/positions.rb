# frozen_string_literal: true

module Managers
  class Positions < Base
    # stop-loss protection
    ATR_MULTIPLIER = 2.5

    def call
      log_info("Postions Manager called at #{Time.zone.now}")

      execute_safely do
        manage_positions
        adjust_stop_loss_for_positions
      end
    end

    private

    # Fetch open positions using the DhanHQ API
    def positions
      Dhanhq::API::Portfolio.positions
    rescue StandardError => e
      log_error('Error fetching positions', e)
      []
    end

    def manage_positions
      positions.each do |position|
        evaluate_and_exit_position(position)
      end
    end

    # Evaluate a position's profit and place a target order if criteria match
    def evaluate_and_exit_position(position)
      profit_percent = calculate_unrealized_profit_percent(position)

      if profit_percent.between?(2.0, 3.0)
        place_limit_exit_order(position)
      else
        log_info("Position #{position['tradingSymbol']} not meeting profit criteria: #{profit_percent}%")
      end
    end

    # Calculate unrealized profit percentage
    def calculate_unrealized_profit_percent(position)
      entry_price = position['buyAvg'].to_f
      unrealized_profit = position['unrealizedProfit'].to_f
      ((unrealized_profit / entry_price) * 100).round(2)
    end

    # Place a limit order to exit the position
    def place_limit_exit_order(position)
      order_params = {
        transactionType: position['positionType'] == 'LONG' ? 'SELL' : 'BUY',
        exchangeSegment: position['exchangeSegment'],
        productType: position['productType'],
        orderType: 'LIMIT',
        securityId: position['securityId'],
        quantity: position['netQty'],
        price: calculate_exit_price(position)
      }

      response = Dhanhq::API::Orders.place(order_params)
      handle_order_response(response, position)
    rescue StandardError => e
      log_error("Failed to place exit order for position #{position['tradingSymbol']}", e)
    end

    # Calculate target exit price
    def calculate_exit_price(position)
      entry_price = position['buyAvg'].to_f
      (entry_price * 1.02).round(2) # 2% profit target
    end

    # Handle the response from the order placement
    def handle_order_response(response, position)
      if response['orderStatus'] == 'PENDING'
        log_info("Exit order placed successfully for position #{position['tradingSymbol']}")
      else
        log_error("Failed to place exit order for position #{position['tradingSymbol']}: #{response['omsErrorDescription']}")
      end
    end

    # Adjust stop-loss dynamically for all open positions
    def adjust_stop_loss_for_positions
      positions.each do |position|
        adjust_stop_loss_for_position(position)
      end
    rescue StandardError => e
      log_error('Error adjusting stop-loss for positions', e)
    end

    def adjust_stop_loss_for_position(position)
      new_stop_loss = calculate_adaptive_stop_loss(position)

      if new_stop_loss > position['costPrice'].to_f
        update_stop_loss(position, new_stop_loss)
      else
        log_info("No adjustment needed for position #{position['tradingSymbol']}")
      end
    end

    def calculate_new_stop_loss(position)
      current_price = position['lastTradedPrice'].to_f
      trailing_amount = position['trailingStopLoss'].to_f

      if position['positionType'] == 'LONG'
        [current_price - trailing_amount, position['stopLossPrice'].to_f].max
      else
        [current_price + trailing_amount, position['stopLossPrice'].to_f].min
      end.round(2)
    end

    def calculate_adaptive_stop_loss(position)
      atr_value = fetch_atr(position)
      entry_price = position['buyAvg'].to_f

      if position['positionType'] == 'LONG'
        (entry_price - (ATR_MULTIPLIER * atr_value)).round(2)
      else
        (entry_price + (ATR_MULTIPLIER * atr_value)).round(2)
      end
    end

    def fetch_atr(position)
      response = Dhanhq::API::MarketFeed.ohlc({ position['exchangeSegment'] => [position['securityId'].to_i] })

      if response['status'] == 'success'
        ohlc_data = response.dig('data', position['exchangeSegment'], position['securityId'].to_s)
        high = ohlc_data['high'].to_f
        low = ohlc_data['low'].to_f
        close = ohlc_data['close'].to_f

        ((high - low).abs + (high - close).abs + (low - close).abs) / 3
      else
        log_error("Failed to fetch ATR for #{position['tradingSymbol']}")
        1.0 # Default ATR
      end
    end

    def update_stop_loss(position, new_stop_loss)
      response = Dhanhq::API::Orders.modify(
        position['orderId'],
        { triggerPrice: new_stop_loss }
      )

      if response['status'] == 'success'
        log_info("Stop-loss updated for position #{position['tradingSymbol']} to #{new_stop_loss}")
      else
        log_error("Failed to update stop-loss for position #{position['tradingSymbol']}: #{response['omsErrorDescription']}")
      end
    rescue StandardError => e
      log_error("Error updating stop-loss for position #{position['tradingSymbol']}", e)
    end
  end
end
