# frozen_string_literal: true

require 'mcp'
require 'dhan_hq'

class DhanMcpService
  def self.build_server
    server = MCP::Server.new(
      name: 'dhan_mcp_server',
      title: 'DhanHQ Broker Data & Market Tools',
      version: '0.1.0',
      instructions: 'Read-only access to DhanHQ v2 APIs. Instrument lookup uses DhanHQ::Models::Instrument.find(exchange_segment, symbol) only—requires both exchange_segment and exact symbol (e.g. NSE_EQ/RELIANCE, IDX_I/NIFTY). Market and historical tools use the same. Uses the DhanHQ gem (https://github.com/shubhamtaywade82/dhanhq-client).',
      server_context: {}
    )
    new(server).define_tools
    server
  end

  def initialize(server)
    @server = server
  end

  def define_tools
    svc = self
    fmt = lambda { |data|
      text = data.is_a?(Hash) && data[:error] ? "Error: #{data[:error]}" : "```json\n#{JSON.pretty_generate(data)}\n```"
      MCP::Tool::Response.new([{ type: 'text', text: text }])
    }
    define_holdings(svc, fmt)
    define_positions(svc, fmt)
    define_fund_limits(svc, fmt)
    define_order_list(svc, fmt)
    define_order_by_id(svc, fmt)
    define_order_by_correlation_id(svc, fmt)
    define_trade_book(svc, fmt)
    define_trade_history(svc, fmt)
    define_instrument(svc, fmt)
    define_historical_daily_data(svc, fmt)
    define_intraday_minute_data(svc, fmt)
    define_market_ohlc(svc, fmt)
    define_option_chain(svc, fmt)
    define_expiry_list(svc, fmt)
    define_edis_inquiry(svc, fmt)
    self
  end

  private

  def dhan_configured?
    ENV['CLIENT_ID'].present? && ENV['ACCESS_TOKEN'].present?
  end

  def dhan(fmt)
    unless dhan_configured?
      return fmt.call({ error: 'Dhan credentials not configured. Set CLIENT_ID and ACCESS_TOKEN (used by DhanHQ.configure_with_env).' })
    end

    data = yield
    fmt.call(to_jsonable(data))
  rescue StandardError => e
    fmt.call({ error: e.message })
  end

  def to_jsonable(obj)
    case obj
    when Array then obj.map { |x| to_jsonable(x) }
    when Hash then obj
    when NilClass then nil
    else
      if obj.respond_to?(:to_h)
        to_jsonable(obj.to_h)
      elsif obj.respond_to?(:attributes)
        to_jsonable(obj.attributes)
      else
        obj
      end
    end
  end

  def resolve_instrument(exchange_segment, symbol)
    inst = ::DhanHQ::Models::Instrument.find(exchange_segment.to_s, symbol.to_s)
    raise "Instrument not found: #{exchange_segment} / #{symbol}" if inst.nil?

    inst
  end

  def define_holdings(svc, fmt)
    @server.define_tool(
      name: 'get_holdings',
      description: 'Retrieve current portfolio holdings.',
      input_schema: { properties: {} }
    ) { |server_context:| svc.send(:dhan, fmt) { ::DhanHQ::Models::Holding.all } }
  end

  def define_positions(svc, fmt)
    @server.define_tool(
      name: 'get_positions',
      description: 'Retrieve current open positions (intraday and delivery).',
      input_schema: { properties: {} }
    ) { |server_context:| svc.send(:dhan, fmt) { ::DhanHQ::Models::Position.all } }
  end

  def define_fund_limits(svc, fmt)
    @server.define_tool(
      name: 'get_fund_limits',
      description: 'Retrieve available funds, margins, and limits.',
      input_schema: { properties: {} }
    ) { |server_context:| svc.send(:dhan, fmt) { ::DhanHQ::Models::Funds.fetch } }
  end

  def define_order_list(svc, fmt)
    @server.define_tool(
      name: 'get_order_list',
      description: "Retrieve the full list of orders (today's and historical).",
      input_schema: { properties: {} }
    ) { |server_context:| svc.send(:dhan, fmt) { ::DhanHQ::Models::Order.all } }
  end

  def define_order_by_id(svc, fmt)
    @server.define_tool(
      name: 'get_order_by_id',
      description: 'Retrieve details for a specific order by Dhan order ID.',
      input_schema: {
        properties: { order_id: { type: 'string', description: 'The Dhan order ID' } },
        required: ['order_id']
      }
    ) do |order_id:, server_context:|
      if (err = DhanMcp::ArgumentValidator.validate('get_order_by_id', { order_id: order_id }))
        fmt.call({ error: err })
      else
        svc.send(:dhan, fmt) { ::DhanHQ::Models::Order.find(order_id) }
      end
    end
  end

  def define_order_by_correlation_id(svc, fmt)
    @server.define_tool(
      name: 'get_order_by_correlation_id',
      description: 'Retrieve order details by correlation ID.',
      input_schema: {
        properties: { correlation_id: { type: 'string', description: 'The correlation ID' } },
        required: ['correlation_id']
      }
    ) do |correlation_id:, server_context:|
      if (err = DhanMcp::ArgumentValidator.validate('get_order_by_correlation_id', { correlation_id: correlation_id }))
        fmt.call({ error: err })
      else
        svc.send(:dhan, fmt) { ::DhanHQ::Models::Order.find_by(correlation: correlation_id) }
      end
    end
  end

  def define_trade_book(svc, fmt)
    @server.define_tool(
      name: 'get_trade_book',
      description: 'Retrieve executed trades for a specific order.',
      input_schema: {
        properties: { order_id: { type: 'string', description: 'The Dhan order ID' } },
        required: ['order_id']
      }
    ) do |order_id:, server_context:|
      if (err = DhanMcp::ArgumentValidator.validate('get_trade_book', { order_id: order_id }))
        fmt.call({ error: err })
      else
        svc.send(:dhan, fmt) { ::DhanHQ::Models::Trade.find_by(order_id: order_id) }
      end
    end
  end

  def define_trade_history(svc, fmt)
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
    ) do |from_date:, to_date:, server_context:, page_number: 0|
      args = { from_date: from_date, to_date: to_date, page_number: page_number }
      if (err = DhanMcp::ArgumentValidator.validate('get_trade_history', args))
        fmt.call({ error: err })
      else
        svc.send(:dhan, fmt) { ::DhanHQ::Models::Trade.history(from_date: from_date, to_date: to_date, page: page_number) }
      end
    end
  end

  def define_instrument(svc, fmt)
    @server.define_tool(
      name: 'get_instrument',
      description: 'Resolve instrument by exchange_segment and exact symbol (DhanHQ::Models::Instrument.find). Requires both. Returns trading fields: isin, bracket_flag, cover_flag, asm_gsm_flag, buy_sell_indicator, mtf_leverage, etc. Segment enums: IDX_I, NSE_EQ, NSE_FNO, BSE_EQ, NSE_CURRENCY, MCX_COMM, BSE_CURRENCY, BSE_FNO.',
      input_schema: {
        properties: {
          exchange_segment: { type: 'string', description: 'Segment: IDX_I, NSE_EQ, NSE_FNO, BSE_EQ, etc.' },
          symbol: { type: 'string', description: 'Exact trading / underlying symbol (e.g. NIFTY, RELIANCE)' }
        },
        required: %w[exchange_segment symbol]
      }
    ) do |exchange_segment:, symbol:, server_context:|
      args = { exchange_segment: exchange_segment, symbol: symbol }
      if (err = DhanMcp::ArgumentValidator.validate('get_instrument', args))
        fmt.call({ error: err })
      else
        svc.send(:dhan, fmt) { svc.send(:resolve_instrument, exchange_segment, symbol) }
      end
    end
  end

  def define_historical_daily_data(svc, fmt)
    @server.define_tool(
      name: 'get_historical_daily_data',
      description: 'Retrieve historical daily candle data. Uses exchange_segment and symbol (e.g. IDX_I/NIFTY, NSE_EQ/RELIANCE).',
      input_schema: {
        properties: {
          exchange_segment: { type: 'string', description: 'Segment: IDX_I, NSE_EQ, NSE_FNO, BSE_EQ, etc.' },
          symbol: { type: 'string', description: 'Trading symbol / underlying symbol (e.g. NIFTY, RELIANCE)' },
          from_date: { type: 'string', description: 'YYYY-MM-DD' },
          to_date: { type: 'string', description: 'YYYY-MM-DD' }
        },
        required: %w[exchange_segment symbol from_date to_date]
      }
    ) do |exchange_segment:, symbol:, from_date:, to_date:, server_context:|
      args = { exchange_segment: exchange_segment, symbol: symbol, from_date: from_date, to_date: to_date }
      if (err = DhanMcp::ArgumentValidator.validate('get_historical_daily_data', args))
        fmt.call({ error: err })
      else
        svc.send(:dhan, fmt) { svc.send(:resolve_instrument, exchange_segment, symbol).daily(from_date: from_date, to_date: to_date) }
      end
    end
  end

  def define_intraday_minute_data(svc, fmt)
    @server.define_tool(
      name: 'get_intraday_minute_data',
      description: 'Retrieve intraday minute candle data. Uses exchange_segment and symbol.',
      input_schema: {
        properties: {
          exchange_segment: { type: 'string', description: 'Segment: IDX_I, NSE_EQ, NSE_FNO, etc.' },
          symbol: { type: 'string', description: 'Trading symbol (e.g. NIFTY, RELIANCE)' },
          from_date: { type: 'string', description: 'YYYY-MM-DD or YYYY-MM-DD HH:MM:SS' },
          to_date: { type: 'string', description: 'YYYY-MM-DD or YYYY-MM-DD HH:MM:SS' },
          interval: { type: 'string', description: 'Minutes: 1, 5, 15, 25, or 60 (default 1)', default: '1' }
        },
        required: %w[exchange_segment symbol from_date to_date]
      }
    ) do |exchange_segment:, symbol:, from_date:, to_date:, server_context:, interval: '1'|
      args = { exchange_segment: exchange_segment, symbol: symbol, from_date: from_date, to_date: to_date, interval: interval }
      if (err = DhanMcp::ArgumentValidator.validate('get_intraday_minute_data', args))
        fmt.call({ error: err })
      else
        from_ts = from_date.to_s.include?(' ') ? from_date : "#{from_date} 09:15:00"
        to_ts = to_date.to_s.include?(' ') ? to_date : "#{to_date} 15:30:00"
        svc.send(:dhan, fmt) do
          svc.send(:resolve_instrument, exchange_segment, symbol).intraday(
            from_date: from_ts, to_date: to_ts, interval: interval
          )
        end
      end
    end
  end

  def define_market_ohlc(svc, fmt)
    @server.define_tool(
      name: 'get_market_ohlc',
      description: 'Retrieve current OHLC for a security. Uses exchange_segment and symbol (e.g. NSE_EQ/RELIANCE, IDX_I/NIFTY).',
      input_schema: {
        properties: {
          exchange_segment: { type: 'string', description: 'Segment: IDX_I, NSE_EQ, NSE_FNO, etc.' },
          symbol: { type: 'string', description: 'Trading symbol (e.g. RELIANCE, NIFTY)' }
        },
        required: %w[exchange_segment symbol]
      }
    ) do |exchange_segment:, symbol:, server_context:|
      args = { exchange_segment: exchange_segment, symbol: symbol }
      if (err = DhanMcp::ArgumentValidator.validate('get_market_ohlc', args))
        fmt.call({ error: err })
      else
        svc.send(:dhan, fmt) { svc.send(:resolve_instrument, exchange_segment, symbol).ohlc }
      end
    end
  end

  def define_option_chain(svc, fmt)
    @server.define_tool(
      name: 'get_option_chain',
      description: 'Retrieve full option chain for an underlying. Uses exchange_segment and underlying symbol.',
      input_schema: {
        properties: {
          exchange_segment: { type: 'string', description: 'Underlying segment (e.g. NSE_FNO)' },
          symbol: { type: 'string', description: 'Underlying symbol (e.g. NIFTY, RELIANCE)' },
          expiry: { type: 'string', description: 'Expiry date YYYY-MM-DD' }
        },
        required: %w[exchange_segment symbol expiry]
      }
    ) do |exchange_segment:, symbol:, expiry:, server_context:|
      args = { exchange_segment: exchange_segment, symbol: symbol, expiry: expiry }
      if (err = DhanMcp::ArgumentValidator.validate('get_option_chain', args))
        fmt.call({ error: err })
      else
        svc.send(:dhan, fmt) { svc.send(:resolve_instrument, exchange_segment, symbol).option_chain(expiry: expiry) }
      end
    end
  end

  def define_expiry_list(svc, fmt)
    @server.define_tool(
      name: 'get_expiry_list',
      description: 'Retrieve expiry dates for an underlying. Uses exchange_segment and symbol.',
      input_schema: {
        properties: {
          exchange_segment: { type: 'string', description: 'Underlying segment (e.g. NSE_FNO)' },
          symbol: { type: 'string', description: 'Underlying symbol (e.g. NIFTY, RELIANCE)' }
        },
        required: %w[exchange_segment symbol]
      }
    ) do |exchange_segment:, symbol:, server_context:|
      args = { exchange_segment: exchange_segment, symbol: symbol }
      if (err = DhanMcp::ArgumentValidator.validate('get_expiry_list', args))
        fmt.call({ error: err })
      else
        svc.send(:dhan, fmt) { svc.send(:resolve_instrument, exchange_segment, symbol).expiry_list }
      end
    end
  end

  def define_edis_inquiry(svc, fmt)
    @server.define_tool(
      name: 'get_edis_inquiry',
      description: 'Retrieve eDIS (electronic delivery instruction slip) inquiry status.',
      input_schema: { properties: {} }
    ) { |server_context:| svc.send(:dhan, fmt) { ::DhanHQ::Models::Edis.inquire('ALL') } }
  end
end
