# frozen_string_literal: true

module DhanMcp
  # Global Stocks (US equities) tools for DhanHQ MCP.
  #
  # This book is separate from the domestic one in every way that matters to a
  # caller: balances and prices are USD, `security_id` is a ticker ("AAPL")
  # rather than a numeric scrip id, quantities may be fractional, and orders
  # carry no exchange segment, product type or validity.
  #
  # Reads are exposed here directly. Writes are not: order placement stays
  # behind `Orders::Gateway` so the PLACE_ORDER / LIVE_TRADING gates and the
  # reconciliation path apply to the US book exactly as they do domestically.
  class GlobalStocksTools < BaseTool
    def define(fmt)
      define_global_holdings(fmt)
      define_global_funds(fmt)
      define_global_orders(fmt)
      define_global_trades(fmt)
      define_global_market_status(fmt)
      define_global_order_estimate(fmt)
    end

    private

    def define_global_holdings(fmt)
      simple_tool(fmt, 'get_global_holdings', 'Retrieve US equity holdings (USD).') do
        ::DhanHQ::Models::GlobalStocks::Holding.all
      end
    end

    def define_global_funds(fmt)
      simple_tool(fmt, 'get_global_funds', 'Retrieve US trading account balance and buying power (USD).') do
        ::DhanHQ::Models::GlobalStocks::Funds.fetch
      end
    end

    def define_global_orders(fmt)
      simple_tool(fmt, 'get_global_orders', 'Retrieve the US equity order book for the day.') do
        ::DhanHQ::Models::GlobalStocks::Order.all
      end
    end

    def define_global_trades(fmt)
      simple_tool(fmt, 'get_global_trades', 'Retrieve executed US equity trades.') do
        ::DhanHQ::Models::GlobalStocks::Trade.all
      end
    end

    def define_global_market_status(fmt)
      simple_tool(fmt, 'get_global_market_status',
                  'Check whether the US market is currently open. US hours differ from NSE/BSE.') do
        ::DhanHQ::Models::GlobalStocks::MarketStatus.fetch
      end
    end

    # Combines brokerage charges and margin for a prospective US order, so an
    # assistant can price a trade before proposing it.
    def define_global_order_estimate(fmt)
      normalize = method(:normalized_args)
      validator = method(:validate)
      dhan_call = ->(&block) { dhan(fmt, &block) }

      @server.define_tool(
        name: 'get_global_order_estimate',
        description: 'Estimate charges and margin for a prospective US equity order (USD). Read-only; places nothing.',
        input_schema: {
          properties: {
            security_id: { type: 'string', description: 'US ticker, e.g. AAPL' },
            transaction_type: { type: 'string', description: 'BUY or SELL' },
            quantity: { type: 'number', description: 'Share count; may be fractional' },
            price: { type: 'number', description: 'Limit price in USD' }
          },
          required: %w[security_id transaction_type quantity price]
        }
      ) do |params: nil, **kwargs|
        args = normalize.call(params: params, **kwargs)
        if (err = validator.call('get_global_order_estimate', args))
          fmt.call({ error: err })
        else
          dhan_call.call do
            ::DhanHQ::Models::GlobalStocks::OrderEstimate.estimate(
              security_id: args[:security_id].to_s,
              transaction_type: args[:transaction_type].to_s.upcase,
              quantity: args[:quantity].to_f,
              price: args[:price].to_f
            )
          end
        end
      end
    end

    # Defines a no-argument read tool.
    def simple_tool(fmt, name, description, &fetch)
      normalize = method(:normalized_args)
      validator = method(:validate)
      dhan_call = ->(&block) { dhan(fmt, &block) }

      @server.define_tool(name: name, description: description, input_schema: { properties: {} }) do |params: nil, **kwargs|
        args = normalize.call(params: params, **kwargs)
        if (err = validator.call(name, args))
          fmt.call({ error: err })
        else
          dhan_call.call(&fetch)
        end
      end
    end
  end
end
