# MCP (Model Context Protocol) — DhanHQ Tools

The app exposes a **read-only** DhanHQ MCP server over HTTP. AI assistants (e.g. Cursor) and other MCP clients can call Dhan broker and market tools via JSON-RPC.

## Endpoint

| Environment | URL |
|-------------|-----|
| **Production** | `https://algo-trading-api.onrender.com/mcp` |
| **Local** | `http://localhost:5002/mcp` (or `PORT` from `.env`) |

- **Method**: `POST`
- **Content-Type**: `application/json`
- **Body**: JSON-RPC 2.0 request (see examples below).

Empty or invalid JSON body returns **400** with a JSON-RPC parse error.

## Argument validation

The server validates tool arguments **before** calling the Dhan API. Invalid or missing arguments produce a clear error in `result.content[].text` (e.g. `"Error: Missing required argument(s): symbol"`), so the model can correct and retry.

Validation rules:

| Rule | Applies to | Example |
|------|------------|---------|
| **Required args** | All tools with params | `get_instrument` needs `exchange_segment` and `symbol` |
| **Non-empty strings** | `order_id`, `correlation_id`, `symbol`, etc. | `"symbol": ""` → error |
| **exchange_segment** | Instrument/market/options tools | Must be one of: `IDX_I`, `NSE_EQ`, `NSE_FNO`, `BSE_EQ`, `NSE_CURRENCY`, `MCX_COMM`, `BSE_CURRENCY`, `BSE_FNO` |
| **Dates** | `from_date`, `to_date`, `expiry` | `YYYY-MM-DD` for daily/history/expiry; `YYYY-MM-DD` or `YYYY-MM-DD HH:MM:SS` for intraday |
| **to_date / from_date** | `get_trade_history`, `get_historical_daily_data`, `get_intraday_minute_data` | **to_date must be today.** **from_date must be the last trading day before to_date** (NSE/BSE calendar via `MarketCalendar`). Any other combination is rejected. |
| **interval** | `get_intraday_minute_data` | One of: `1`, `5`, `15`, `25`, `60` |
| **page_number** | `get_trade_history` | Non-negative integer |

Implementation: `DhanMcp::ArgumentValidator` (see `app/services/dhan_mcp/argument_validator.rb`). Tools with no arguments (e.g. `get_holdings`) are not validated for extra keys.

## Protocol

All requests are JSON-RPC 2.0. To call a tool, use `method: "tools/call"` and pass `name` and `arguments` in `params`.

### Example: call a tool

```bash
curl -s -X POST https://algo-trading-api.onrender.com/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/call",
    "params": {
      "name": "get_instrument",
      "arguments": { "exchange_segment": "IDX_I", "symbol": "SENSEX" }
    }
  }'
```

Responses include `result.content[].text` (often markdown-wrapped JSON) or `error` on failure.

---

## Available tools

Tools use the app’s Dhan credentials (`CLIENT_ID`, `ACCESS_TOKEN`). No extra auth is required when calling the MCP URL.

### Portfolio & funds

| Tool | Description | `arguments` |
|------|-------------|-------------|
| **get_holdings** | Current portfolio holdings | `{}` |
| **get_positions** | Open positions (intraday + delivery) | `{}` |
| **get_fund_limits** | Available funds, margins, limits | `{}` |

### Orders & trades

| Tool | Description | `arguments` |
|------|-------------|-------------|
| **get_order_list** | All orders (today + history) | `{}` |
| **get_order_by_id** | Order by Dhan order ID | `{"order_id": "ORD123"}` |
| **get_order_by_correlation_id** | Order by your correlation ID | `{"correlation_id": "my-ref-1"}` |
| **get_trade_book** | Executed trades for an order | `{"order_id": "ORD123"}` |
| **get_trade_history** | Trades in a date range (paginated) | `{"from_date": "2025-01-01", "to_date": "2025-01-28"}` optional: `"page_number": 0` |

### Instruments & market data

| Tool | Description | `arguments` |
|------|-------------|-------------|
| **get_instrument** | Resolve instrument by segment + symbol | `{"exchange_segment": "NSE_EQ", "symbol": "RELIANCE"}` |
| **get_market_ohlc** | Current OHLC for a symbol | `{"exchange_segment": "NSE_EQ", "symbol": "RELIANCE"}` |
| **get_historical_daily_data** | Daily candle data | `{"exchange_segment": "NSE_EQ", "symbol": "RELIANCE", "from_date": "2025-01-01", "to_date": "2025-01-28"}` |
| **get_intraday_minute_data** | Minute candle data | `{"exchange_segment": "NSE_EQ", "symbol": "RELIANCE", "from_date": "2025-01-28", "to_date": "2025-01-28"}` optional: `"interval": "1"` (1, 5, 15, 25, 60) |

### Options

| Tool | Description | `arguments` |
|------|-------------|-------------|
| **get_expiry_list** | Expiry dates for an underlying | `{"exchange_segment": "NSE_FNO", "symbol": "NIFTY"}` |
| **get_option_chain** | Full option chain for an expiry | `{"exchange_segment": "NSE_FNO", "symbol": "NIFTY", "expiry": "2025-01-30"}` |

### Other

| Tool | Description | `arguments` |
|------|-------------|-------------|
| **get_edis_inquiry** | eDIS inquiry status | `{}` |

---

## Exchange segments

Common `exchange_segment` values:

- **IDX_I** — Index (e.g. NIFTY, SENSEX)
- **NSE_EQ** — NSE equity
- **NSE_FNO** — NSE F&O
- **BSE_EQ** — BSE equity
- **NSE_CURRENCY**, **BSE_CURRENCY** — Currency
- **MCX_COMM** — MCX commodity
- **BSE_FNO** — BSE F&O

---

## Example requests

### Holdings

```bash
curl -s -X POST https://algo-trading-api.onrender.com/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_holdings","arguments":{}}}'
```

### Market OHLC (RELIANCE)

```bash
curl -s -X POST https://algo-trading-api.onrender.com/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_market_ohlc","arguments":{"exchange_segment":"NSE_EQ","symbol":"RELIANCE"}}}'
```

### NIFTY expiry list

```bash
curl -s -X POST https://algo-trading-api.onrender.com/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_expiry_list","arguments":{"exchange_segment":"NSE_FNO","symbol":"NIFTY"}}}'
```

### Instrument (SENSEX)

```bash
curl -s -X POST https://algo-trading-api.onrender.com/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_instrument","arguments":{"exchange_segment":"IDX_I","symbol":"SENSEX"}}}'
```

---

## Using from Cursor

1. Ensure the app is deployed and `/mcp` is reachable (e.g. `https://algo-trading-api.onrender.com/mcp`).
2. In Cursor, add an **HTTP** MCP server:
   - **URL**: `https://algo-trading-api.onrender.com/mcp`
3. Cursor will then be able to use the tools in this project (holdings, positions, orders, market data, options, etc.).

A local config example lives in `.cursor/mcp.json`; you can point it at the production URL when using the deployed app.

---

## Implementation notes

- **Controller**: `McpController#index` — reads body, returns 400 when body is blank, otherwise forwards to the MCP server.
- **Service**: `DhanMcpService` — builds the `MCP::Server`, defines all tools, and uses the DhanHQ gem under the hood. Each tool that takes arguments runs `DhanMcp::ArgumentValidator.validate(tool_name, args)` before calling Dhan; invalid args return an error string in the usual `Error: …` format.
- **Validator**: `DhanMcp::ArgumentValidator` — validates required/optional args, `exchange_segment` enum, date formats, `interval`, and `page_number`. Returns `nil` if valid, or a short error message string.
- **Config**: `config/initializers/dhan_mcp.rb` — builds the server at boot and stores it in `Rails.application.config.x.dhan_mcp_server`.
- **Route**: `POST /mcp` → `mcp#index`.

All tools are read-only; no orders or modifications are performed via the MCP.

**Running MCP specs:** `bundle exec rspec --tag mcp`
