# frozen_string_literal: true

module DhanMcp
  # Market-related tools for DhanHQ MCP.
  class MarketTools < BaseTool
    def define(fmt)
      define_instrument(fmt)
      define_historical_daily_data(fmt)
      define_intraday_minute_data(fmt)
      define_market_ohlc(fmt)
      define_option_chain(fmt)
      define_expiry_list(fmt)
    end

    private

    def define_instrument(fmt)
      @server.define_tool(
        name: 'get_instrument',
        description: 'Resolve instrument by segment and symbol. ' \
                     'Returns: isin, bracket_flag, cover_flag, etc. ' \
                     'Segments: IDX_I, NSE_EQ, NSE_FNO, BSE_EQ, etc.',
        input_schema: {
          properties: {
            exchange_segment: { type: 'string', description: 'Segment: IDX_I, NSE_EQ, NSE_FNO, etc.' },
            symbol: { type: 'string', description: 'Exact trading symbol (e.g. NIFTY, RELIANCE)' }
          },
          required: %w[exchange_segment symbol]
        }
      ) do |exchange_segment:, symbol:, **_|
        args = { exchange_segment: exchange_segment, symbol: symbol }
        if (err = validate('get_instrument', args))
          fmt.call({ error: err })
        else
          dhan(fmt) { resolve_instrument(exchange_segment, symbol) }
        end
      end
    end

    def define_historical_daily_data(fmt)
      @server.define_tool(
        name: 'get_historical_daily_data',
        description: 'Retrieve historical daily candle data.',
        input_schema: {
          properties: {
            exchange_segment: { type: 'string', description: 'Segment: IDX_I, NSE_EQ, etc.' },
            symbol: { type: 'string', description: 'Trading symbol (e.g. NIFTY, RELIANCE)' },
            from_date: { type: 'string', description: 'YYYY-MM-DD' },
            to_date: { type: 'string', description: 'YYYY-MM-DD' }
          },
          required: %w[exchange_segment symbol from_date to_date]
        }
      ) do |exchange_segment:, symbol:, from_date:, to_date:, **_|
        args = { exchange_segment: exchange_segment, symbol: symbol, from_date: from_date, to_date: to_date }
        if (err = validate('get_historical_daily_data', args))
          fmt.call({ error: err })
        else
          dhan(fmt) { resolve_instrument(exchange_segment, symbol).daily(from_date: from_date, to_date: to_date) }
        end
      end
    end

    def define_intraday_minute_data(fmt)
      @server.define_tool(
        name: 'get_intraday_minute_data',
        description: 'Retrieve intraday minute candle data.',
        input_schema: {
          properties: {
            exchange_segment: { type: 'string', description: 'Segment: IDX_I, NSE_EQ, etc.' },
            symbol: { type: 'string', description: 'Trading symbol (e.g. NIFTY, RELIANCE)' },
            from_date: { type: 'string', description: 'YYYY-MM-DD or YYYY-MM-DD HH:MM:SS' },
            to_date: { type: 'string', description: 'YYYY-MM-DD or YYYY-MM-DD HH:MM:SS' },
            interval: { type: 'string', description: 'Minutes: 1, 5, 15, 25, or 60 (default 1)', default: '1' }
          },
          required: %w[exchange_segment symbol from_date to_date]
        }
      ) do |exchange_segment:, symbol:, from_date:, to_date:, interval: '1', **_|
        args = { exchange_segment: exchange_segment, symbol: symbol, from_date: from_date, to_date: to_date, interval: interval }
        if (err = validate('get_intraday_minute_data', args))
          fmt.call({ error: err })
        else
          from_ts = from_date.to_s.include?(' ') ? from_date : "#{from_date} 09:15:00"
          to_ts = to_date.to_s.include?(' ') ? to_date : "#{to_date} 15:30:00"
          dhan(fmt) do
            resolve_instrument(exchange_segment, symbol).intraday(
              from_date: from_ts, to_date: to_ts, interval: interval
            )
          end
        end
      end
    end

    def define_market_ohlc(fmt)
      @server.define_tool(
        name: 'get_market_ohlc',
        description: 'Retrieve current OHLC for a security.',
        input_schema: {
          properties: {
            exchange_segment: { type: 'string', description: 'Segment: IDX_I, NSE_EQ, etc.' },
            symbol: { type: 'string', description: 'Trading symbol (e.g. RELIANCE, NIFTY)' }
          },
          required: %w[exchange_segment symbol]
        }
      ) do |exchange_segment:, symbol:, **_|
        args = { exchange_segment: exchange_segment, symbol: symbol }
        if (err = validate('get_market_ohlc', args))
          fmt.call({ error: err })
        else
          dhan(fmt) { resolve_instrument(exchange_segment, symbol).ohlc }
        end
      end
    end

    def define_option_chain(fmt)
      @server.define_tool(
        name: 'get_option_chain',
        description: 'Retrieve full option chain for an underlying.',
        input_schema: {
          properties: {
            exchange_segment: { type: 'string', description: 'Underlying segment (e.g. NSE_FNO)' },
            symbol: { type: 'string', description: 'Underlying symbol (e.g. NIFTY, RELIANCE)' },
            expiry: { type: 'string', description: 'Expiry date YYYY-MM-DD' }
          },
          required: %w[exchange_segment symbol expiry]
        }
      ) do |exchange_segment:, symbol:, expiry:, **_|
        args = { exchange_segment: exchange_segment, symbol: symbol, expiry: expiry }
        if (err = validate('get_option_chain', args))
          fmt.call({ error: err })
        else
          dhan(fmt) { resolve_instrument(exchange_segment, symbol).option_chain(expiry: expiry) }
        end
      end
    end

    def define_expiry_list(fmt)
      @server.define_tool(
        name: 'get_expiry_list',
        description: 'Retrieve expiry dates for an underlying. ' \
                     'IDX_I for indices (NIFTY), NSE_EQ for stocks.',
        input_schema: {
          properties: {
            exchange_segment: { type: 'string', description: 'Underlying segment (IDX_I, NSE_EQ)' },
            symbol: { type: 'string', description: 'Underlying symbol (e.g. NIFTY, RELIANCE)' }
          },
          required: %w[exchange_segment symbol]
        }
      ) do |exchange_segment:, symbol:, **_|
        args = { exchange_segment: exchange_segment, symbol: symbol }
        if (err = validate('get_expiry_list', args))
          fmt.call({ error: err })
        else
          dhan(fmt) { resolve_instrument(exchange_segment, symbol).expiry_list }
        end
      end
    end
  end
end
