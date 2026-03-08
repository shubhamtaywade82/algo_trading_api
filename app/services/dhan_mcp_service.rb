# frozen_string_literal: true

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
    fmt = lambda { |data|
      text = data.is_a?(Hash) && data[:error] ? "Error: #{data[:error]}" : "```json\n#{JSON.pretty_generate(data)}\n```"
      MCP::Tool::Response.new([{ type: 'text', text: text }])
    }

    DhanMcp::PortfolioTools.define(@server, self).define(fmt)
    DhanMcp::OrderTools.define(@server, self).define(fmt)
    DhanMcp::MarketTools.define(@server, self).define(fmt)
    DhanMcp::AccountTools.define(@server, self).define(fmt)
    self
  end

  private

  def dhan_configured?
    client_id_present?
  end

  def client_id_present?
    ENV['DHAN_CLIENT_ID'].present? || ENV['CLIENT_ID'].present?
  end

  def dhan(fmt)
    unless dhan_configured?
      return fmt.call({ error: 'Dhan not connected. Set DHAN_CLIENT_ID (or CLIENT_ID) and complete login at /auth/dhan/login.' })
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
end
