# frozen_string_literal: true

module AlertProcessors
  # Processes TradingView alerts for **cash-equity** instruments.
  # ──────────────────────────────────────────────────────────────
  # ▸ Intraday  →  INTRADAY product, long+short allowed
  # ▸ Swing     →  CNC product, *long-only*; short_entry/short_exit are ignored.
  # ▸ Long-term →  CNC product, *long-only*; short_entry/short_exit are ignored.
  #
  # Every alert goes through a three-step pipeline:
  #   1.  signal_guard!     ▸ aborts if the signal is impossible / duplicated
  #   2.  build_order!      ▸ creates a Dhan order-payload with proper sizing
  #   3.  execute_order!    ▸ either places it (ENV['PLACE_ORDER']=='true')
  #                          or just logs the JSON for dry-runs
  #
  # After a successful execution the alert row is updated and, if CNC stock was
  # sold, we trigger eDIS automatically (Dhan API § “EDIS”) so that the sell-
  # trade can actually settle. :contentReference[oaicite:0]{index=0}&#8203;:contentReference[oaicite:1]{index=1}
  #
  class Stock < Base
    FUNDS_UTILIZATION = 0.3 # % of Total equity can be used

    PRODUCT_TYPE_FOR = {
      'intraday' => Dhanhq::Constants::INTRA, # leverage allowed
      'swing' => Dhanhq::Constants::CNC,      # delivery
      'long_term' => Dhanhq::Constants::CNC   # delivery
    }.freeze

    LONG_ONLY_STRATEGIES = %w[swing long_term].freeze
    LONG_SIGNALS         = %w[long_entry long_exit].freeze
    SHORT_SIGNALS        = %w[short_entry short_exit].freeze

    EDIS_POLL_INTERVAL = 5.seconds
    EDIS_TIMEOUT       = 45.seconds

    # The main entry point for processing a stock alert.
    # Based on `alert[:strategy_type]`, it calls the relevant private method:
    #  - `process_intraday_strategy`
    #  - `process_swing_strategy`
    #  - `process_long_term_strategy`
    #
    # If it fails at any step, the alert status is updated to "failed",
    # with the error message logged. Otherwise, the alert status is set to "processed".
    #
    # @return [void]
    def call
      Rails.logger.info("Stock-alert received ⇒ #{alert.inspect}")

      # Abort early if the signal makes no sense for the chosen strategy_type
      signal_guard!

      # Build + send (or log) the order
      payload = build_order_payload!
      execute_order!(payload)

      # unless trade_signal_valid?
      #   alert.update(status: 'skipped', error_message: 'Signal type did not match current position.')
      #   return
      # end

      # case alert[:strategy_type]
      # when 'intraday'
      #   process_intraday_strategy
      # when 'swing'
      #   process_swing_strategy
      # when 'long_term'
      #   process_long_term_strategy
      # else
      #   raise "Unsupported strategy type: #{alert[:strategy_type]}"
      # end

      alert.update!(status: 'processed')
    rescue StandardError => e
      alert.update!(status: 'failed', error_message: e.message)
      Rails.logger.error("Stock alert failed ⇒ #{e.message}")
    end

    private

    # GUARD-CLAUSES
    def signal_guard!
      # 1-a  Are we trying to short-sell in swing / long-term?
      if LONG_ONLY_STRATEGIES.include?(alert[:strategy_type]) &&
         SHORT_SIGNALS.include?(alert[:signal_type])
        raise "Short-selling is not supported for #{alert[:strategy_type]} " \
              'strategies on cash equities (Dhan CNC).'
      end

      # 1-b  Do we already hold / not hold the stock?
      current_net_qty = fetch_current_net_quantity # positive, negative, or 0

      case alert[:signal_type]
      when 'long_entry'
        raise 'Already in a long position.' if current_net_qty.positive?
      when 'long_exit'
        raise 'No long position to exit.'    if current_net_qty.zero?
      when 'short_entry'
        raise 'Already in a short position.' if current_net_qty.negative?
      when 'short_exit'
        raise 'No short position to exit.'   if current_net_qty.zero?
      end
    end

    def build_order_payload!
      product = PRODUCT_TYPE_FOR.fetch(alert[:strategy_type])
      transaction_type =
        case alert[:signal_type]
        when 'long_entry',  'short_exit'  then 'BUY'
        when 'long_exit',   'short_entry' then 'SELL'
        else raise "Unknown signal_type #{alert[:signal_type]}"
        end

      {
        transactionType: transaction_type,
        orderType: alert[:order_type].upcase, # MARKET / LIMIT
        productType: product,
        validity: Dhanhq::Constants::DAY,
        exchangeSegment: instrument.exchange_segment,
        securityId: instrument.security_id,
        quantity: calculate_quantity!(product, transaction_type),
        price: ltp, # 0 for MARKET
        triggerPrice: alert[:stop_price] || 0
      }
    end

    # position-size for CNC (no leverage) = risk_% × available_balance / price
    RISK_PER_TRADE      = 0.02   # 2 % of account per CNC position
    SWING_MAX_FRACTION  = 0.50   # never tie up more than 50 % of funds
    INTRADAY_FRACTION   = 0.30

    # BUY / SELL
    def calculate_quantity!(product, transaction_type)
      return fetch_current_net_quantity.abs if transaction_type == 'SELL' # exit → just flatten the existing position

      price     = ltp
      balance   = available_balance
      util_frac = product == Dhanhq::Constants::INTRA ? INTRADAY_FRACTION : SWING_MAX_FRACTION
      risk_cap  = balance * RISK_PER_TRADE
      max_cash  = balance * util_frac
      qty_by_risk = (risk_cap / price).floor
      qty_by_cash = (max_cash / price).floor

      quantity = [qty_by_risk, qty_by_cash].min
      raise "Insufficient balance to buy even 1 share of #{instrument.symbol_name}" if quantity.zero?

      quantity
    end

    def execute_order!(payload)
      if ENV['PLACE_ORDER'] == 'true'
        order = Dhanhq::API::Orders.place(payload) # returns { 'orderId'=>… }
        alert.update!(broker_order_id: order['orderId'])

        # If this is the **first** CNC-SELL for that ISIN today → make sure
        # there are enough marked shares. `ensure_edis!` becomes idempotent:
        #
        ensure_edis!(payload[:quantity]) if cnc_sell?(payload)
        Rails.logger.info("✓ Dhan order placed ⇒ #{order}")
      else
        Rails.logger.info("PLACE_ORDER=disabled → #{payload}")
      end
    end

    def cnc_sell?(payload)
      payload[:productType] == Dhanhq::Constants::CNC &&
        payload[:transactionType] == 'SELL'
    end

    def ensure_edis!(needed_qty)
      info = Dhanhq::API::EDIS.status(isin: instrument.isin)

      return if info['status'] == 'SUCCESS' && status['aprvdQty'].to_i >= needed_qty

      # 1️⃣ Mark the shares (once).  Use `bulk:true` so the client need only
      #    enter T-PIN a single time for the day, even if we sell in chunks.
      Rails.logger.info("eDIS: marking #{instrument.isin} for #{needed_qty}")
      Dhanhq::API::EDIS.mark(
        isin: instrument.isin,
        qty: needed_qty,
        exchange: instrument.exchange.upcase,
        segment: 'EQ',
        bulk: true
      )

      # 2️⃣ Poll until CDSL responds “SUCCESS” or we time-out.
      started_at = Time.current
      loop do
        sleep EDIS_POLL_INTERVAL
        info = Dhanhq::API::EDIS.status(isin: instrument.isin)
        break if info['status'] == 'SUCCESS' &&
                 info['aprvdQty'].to_i >= needed_qty

        raise 'eDIS approval timed-out' if Time.current - started_at > EDIS_TIMEOUT
      end
    end

    def fetch_current_net_quantity
      pos = dhan_positions.find { |p| p['securityId'].to_s == instrument.security_id.to_s }
      pos&.dig('netQty').to_i
    end

    # # **Fetch Option Chain for the Stock's Derivative (if exists)**
    # def fetch_option_chain
    #   instrument.fetch_option_chain(@expiry)
    # rescue StandardError => e
    #   Rails.logger.error("Failed to fetch option chain: #{e.message}")
    #   nil
    # end

    # # **Analyze Option Chain for Market Sentiment**
    # def analyze_option_chain(option_chain)
    #   chain_analyzer = Option::ChainAnalyzer.new(
    #     option_chain,
    #     expiry: @expiry,
    #     underlying_spot: option_chain[:last_price],
    #     historical_data: fetch_historical_data
    #   )
    #   chain_analyzer.analyze(
    #     strategy_type: alert[:strategy_type],
    #     instrument_type: segment_from_alert_type(alert[:instrument_type])
    #   )
    # end

    # # **Decide Whether to Execute the Stock Trade Based on Option Chain**
    # def should_trade_based_on_option_chain?(analysis_result)
    #   return true if analysis_result.nil? # If no option chain, proceed normally

    #   sentiment = analysis_result[:sentiment]

    #   if sentiment == 'bullish' && alert[:action] == 'SELL'
    #     Rails.logger.info('Bearish sentiment detected; avoiding short trade.')
    #     return false
    #   elsif sentiment == 'bearish' && alert[:action] == 'BUY'
    #     Rails.logger.info('Bullish sentiment missing; avoiding long trade.')
    #     return false
    #   end

    #   true
    # end

    # # **Fetch basic historical data** e.g. last 5 daily bars for momentum
    # def fetch_historical_data
    #   alert[:strategy_type] == 'intraday' ? fetch_intraday_candles : fetch_short_historical_data
    # end

    # # Example: fetch 5 days of daily candles
    # def fetch_short_historical_data
    #   Dhanhq::API::Historical.daily(
    #     securityId: instrument.security_id,
    #     exchangeSegment: instrument.exchange_segment,
    #     instrument: instrument.instrument_type,
    #     fromDate: 45.days.ago.to_date.to_s,
    #     toDate: Date.yesterday.to_s
    #   )
    # rescue StandardError
    #   []
    # end

    # def fetch_intraday_candles
    #   Dhanhq::API::Historical.intraday(
    #     securityId: instrument.security_id,
    #     exchangeSegment: instrument.exchange_segment,
    #     instrument: instrument.instrument_type,
    #     interval: '5', # 5-min bars
    #     fromDate: 5.days.ago.to_date.to_s,
    #     toDate: Time.zone.today.to_s
    #   )
    # rescue StandardError => e
    #   Rails.logger.error("Failed to fetch intraday data => #{e.message}")
    #   []
    # end

    # # Processes an intraday strategy by building an INTRA order payload
    # # and placing the order.
    # #
    # # @return [void]
    # #
    # def process_intraday_strategy
    #   order_params = build_order_payload(Dhanhq::Constants::INTRA)
    #   place_order(order_params)
    # end

    # # Processes a swing strategy by building a MARGIN order payload
    # # and placing the order.
    # #
    # # @return [void]
    # def process_swing_strategy
    #   order_params = build_order_payload(Dhanhq::Constants::MARGIN)
    #   place_order(order_params)
    # end

    # # Processes a long-term strategy by building a MARGIN order payload
    # # and placing the order.
    # #
    # # @return [void]
    # def process_long_term_strategy
    #   order_params = build_order_payload(Dhanhq::Constants::MARGIN)
    #   place_order(order_params)
    # end

    # # Builds a hash of order parameters common to all strategies, with a
    # # specified product type (e.g., INTRA or MARGIN).
    # #
    # # @param product_type [String] The product type constant (e.g. `Dhanhq::Constants::INTRA`).
    # # @return [Hash] The payload required by the Dhanhq::API::Orders.place method.
    # def build_order_payload(product_type)
    #   quantity = if exit_signal?
    #                fetch_exit_quantity
    #              else
    #                calculate_quantity
    #              end

    #   {
    #     transactionType: alert[:action].upcase,
    #     orderType: alert[:order_type].upcase,
    #     productType: product_type,
    #     validity: Dhanhq::Constants::DAY,
    #     securityId: instrument.security_id,
    #     exchangeSegment: instrument.exchange_segment,
    #     quantity: quantity
    #   }
    # end

    # # Places the order using Dhan API if PLACE_ORDER is set to 'true';
    # # otherwise logs order parameters without placing an order.
    # #
    # # @param order_params [Hash] The order payload to be sent to Dhanhq::API::Orders.place
    # # @return [void]
    # def place_order(order_params)
    #   if ENV['PLACE_ORDER'] == 'true'
    #     executed_order = Dhanhq::API::Orders.place(order_params)
    #     # validate_margin(order_params)
    #     Rails.logger.info("Order placed successfully: #{executed_order}")
    #   else
    #     Rails.logger.info("PLACE_ORDER is disabled. Order parameters: #{order_params}")
    #   end
    # rescue StandardError => e
    #   raise "Failed to place order: #{e.message}"
    # end

    # # Validates margin before placing an order (unused in the current example).
    # # Demonstrates how you might extend functionality, e.g., by calling
    # # Dhanhq::API::Funds.margin_calculator.
    # #
    # # @param params [Hash] A hash of order details used to calculate margin.
    # # @return [Hash] The API response indicating margin details, if successful.
    # def validate_margin(params)
    #   params = params.merge(price: option_chain[:last_price] || ltp)
    #   response = Dhanhq::API::Funds.margin_calculator(params)
    #   response['insufficientBalance']

    #   # raise "Insufficient margin: Missing ₹#{insufficient_balance}" if insufficient_balance.positive?

    #   response
    # rescue StandardError => e
    #   raise "Margin validation failed: #{e.message}"
    # end

    # # Calculates the maximum quantity to trade, ensuring it doesn't exceed
    # # available balance and applies any leverage or lot constraints.
    # #
    # # @param price [Float] The current LTP (Last Traded Price) of the instrument.
    # # @return [Integer] The final computed quantity to trade.
    # def calculate_quantity
    #   min_quantity = minimum_quantity_based_on_ltp
    #   max_quantity = maximum_quantity_based_on_funds

    #   if max_quantity >= min_quantity
    #     max_quantity
    #   else
    #     raise "Insufficient funds: Required minimum quantity for #{instrument.underlying_symbol} at ₹#{option_chain[:last_price] || ltp} is #{min_quantity}, " \
    #           "but available funds allow only #{max_quantity}. Skipping trade."
    #   end
    # end

    # def validate_quantity(quantity)
    #   min_qty = minimum_quantity_based_on_ltp
    #   if quantity < min_qty
    #     Rails.logger.warn("Trade quantity (#{quantity}) is below minimum required (#{min_qty}). Adjusting.")
    #     return min_qty
    #   end

    #   quantity
    # end

    # def maximum_quantity_based_on_funds
    #   effective_funds = available_balance * FUNDS_UTILIZATION

    #   leveraged_price = option_chain[:last_price] || (ltp / leverage_factor)

    #   (effective_funds / leveraged_price).floor
    # end

    # def minimum_quantity_based_on_ltp
    #   case option_chain[:last_price] || ltp
    #   when 0..50
    #     intraday? ? 500 : 250
    #   when 51..200
    #     intraday? ? 100 : 50
    #   when 201..500
    #     intraday? ? 50 : 25
    #   when 501..1000
    #     intraday? ? 10 : 5
    #   else
    #     intraday? ? 5 : 1
    #   end
    # end

    # def intraday?
    #   alert[:strategy_type].upcase == Dhanhq::Constants::INTRA
    # end

    # def exit_signal?
    #   %w[long_exit short_exit].include?(alert[:signal_type])
    # end

    # def fetch_exit_quantity
    #   positions = Dhanhq::API::Portfolio.positions
    #   position = positions.find { |pos| pos['securityId'].to_s == instrument.security_id.to_s }

    #   if position.nil? || position['netQty'].to_i.zero?
    #     raise "No open position found for exit on #{instrument.underlying_symbol}"
    #   end

    #   position['netQty'].abs
    # end

    # def trade_signal_valid?
    #   stock_position = dhan_positions.find { |p| p['securityId'].to_s == instrument.security_id.to_s }

    #   size = stock_position&.dig('netQty').to_i

    #   case alert[:signal_type]
    #   when 'long_entry'
    #     return true if size.zero?

    #     Rails.logger.info("Skipping long_entry — existing position found for #{instrument.underlying_symbol}.")
    #     false

    #   when 'short_entry'
    #     return true if size.zero?

    #     Rails.logger.info("Skipping short_entry — existing position found for #{instrument.underlying_symbol}.")
    #     false

    #   when 'long_exit'
    #     if size.positive?
    #       true
    #     else
    #       Rails.logger.info("Skipping long_exit — no long position open for #{instrument.underlying_symbol}.")
    #       false
    #     end

    #   when 'short_exit'
    #     if size.negative?
    #       true
    #     else
    #       Rails.logger.info("Skipping short_exit — no short position open for #{instrument.underlying_symbol}.")
    #       false
    #     end

    #   else
    #     Rails.logger.warn("Unknown signal_type #{alert[:signal_type]}. Skipping.")
    #     false
    #   end
    # end

    # # Defines the leverage factor based on the alert’s strategy type.
    # # If it's intraday, it returns the MIS leverage (or 1 if undefined).
    # # Otherwise, returns 1x leverage for swing/long_term.
    # #
    # # @return [Float] The numeric leverage multiplier.
    # def leverage_factor
    #   alert[:strategy_type] == 'intraday' ? instrument.mis_detail&.mis_leverage.to_i || 1 : 1.0
    # end
  end
end
