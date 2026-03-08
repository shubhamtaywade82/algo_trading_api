# frozen_string_literal: true

module DhanMcp
  # Order-related tools for DhanHQ MCP.
  class OrderTools < BaseTool
    def define(fmt)
      define_order_list(fmt)
      define_order_by_id(fmt)
      define_order_by_correlation_id(fmt)
      define_trade_book(fmt)
      define_trade_history(fmt)
    end

    private

    def define_order_list(fmt)
      @server.define_tool(
        name: 'get_order_list',
        description: "Retrieve the full list of orders (today's and historical).",
        input_schema: { properties: {} }
      ) { |**_| dhan(fmt) { ::DhanHQ::Models::Order.all } }
    end

    def define_order_by_id(fmt)
      @server.define_tool(
        name: 'get_order_by_id',
        description: 'Retrieve details for a specific order by Dhan order ID.',
        input_schema: {
          properties: { order_id: { type: 'string', description: 'The Dhan order ID' } },
          required: ['order_id']
        }
      ) do |order_id:, **_|
        if (err = validate('get_order_by_id', { order_id: order_id }))
          fmt.call({ error: err })
        else
          dhan(fmt) { ::DhanHQ::Models::Order.find(order_id) }
        end
      end
    end

    def define_order_by_correlation_id(fmt)
      @server.define_tool(
        name: 'get_order_by_correlation_id',
        description: 'Retrieve order details by correlation ID.',
        input_schema: {
          properties: { correlation_id: { type: 'string', description: 'The correlation ID' } },
          required: ['correlation_id']
        }
      ) do |correlation_id:, **_|
        if (err = validate('get_order_by_correlation_id', { correlation_id: correlation_id }))
          fmt.call({ error: err })
        else
          dhan(fmt) { ::DhanHQ::Models::Order.find_by(correlation: correlation_id) }
        end
      end
    end

    def define_trade_book(fmt)
      @server.define_tool(
        name: 'get_trade_book',
        description: 'Retrieve executed trades for a specific order.',
        input_schema: {
          properties: { order_id: { type: 'string', description: 'The Dhan order ID' } },
          required: ['order_id']
        }
      ) do |order_id:, **_|
        if (err = validate('get_trade_book', { order_id: order_id }))
          fmt.call({ error: err })
        else
          dhan(fmt) { ::DhanHQ::Models::Trade.find_by(order_id: order_id) }
        end
      end
    end

    def define_trade_history(fmt)
      @server.define_tool(
        name: 'get_trade_history',
        description: 'Retrieve trade history between dates (paginated).',
        input_schema: {
          properties: {
            from_date: { type: 'string', description: 'Start date (YYYY-MM-DD)' },
            to_date: { type: 'string', description: 'End date (YYYY-MM-DD)' },
            page_number: { type: 'integer', description: 'Page number (default 0)', default: 0 }
          },
          required: %w[from_date to_date]
        }
      ) do |from_date:, to_date:, page_number: 0, **_|
        args = { from_date: from_date, to_date: to_date, page_number: page_number }
        if (err = validate('get_trade_history', args))
          fmt.call({ error: err })
        else
          dhan(fmt) { ::DhanHQ::Models::Trade.history(from_date: from_date, to_date: to_date, page: page_number) }
        end
      end
    end
  end
end
