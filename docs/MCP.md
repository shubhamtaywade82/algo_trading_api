# MCP (Model Context Protocol) — DhanHQ Tools

The app exposes a **read-only** DhanHQ MCP server over HTTP. AI assistants (e.g. Cursor) and other MCP clients can call Dhan broker and market tools via JSON-RPC.

## Endpoint

| Environment  | URL                                                   |
| ------------ | ----------------------------------------------------- |
| **Local**    | `http://localhost:5002/mcp` (or `PORT` from `.env`)   |
| **Deployed** | `https://YOUR_APP_HOST/mcp` (use your app’s base URL) |

- **Method**: `POST`
- **Content-Type**: `application/json`
- **Body**: JSON-RPC 2.0 request (see examples below).

Empty or invalid JSON body returns **400** with a JSON-RPC parse error.

### Production: authentication and limits

- **Authentication** — When `MCP_ACCESS_TOKEN` is set in the environment, the server requires `Authorization: Bearer <token>` on every request. Missing or invalid token returns **401** with a JSON-RPC error. When `MCP_ACCESS_TOKEN` is not set (e.g. local dev), no auth is required.
- **Request body size** — Requests with `Content-Length` greater than 1 MB are rejected with **413** (Payload Too Large) and a JSON-RPC error.

Set `MCP_ACCESS_TOKEN` in production (e.g. Render dashboard → Environment) and configure clients to send the same value as a Bearer token. Use a long, random secret (e.g. `openssl rand -hex 32`).

## Argument validation

The server validates tool arguments **before** calling the Dhan API. Invalid or missing arguments produce a clear error in `result.content[].text` (e.g. `"Error: Missing required argument(s): symbol"`), so the model can correct and retry.

Validation rules:

| Rule                    | Applies to                                                                   | Example                                                                                                                                                          |
| ----------------------- | ---------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Required args**       | All tools with params                                                        | `get_instrument` needs `exchange_segment` and `symbol`                                                                                                           |
| **Non-empty strings**   | `order_id`, `correlation_id`, `symbol`, etc.                                 | `"symbol": ""` → error                                                                                                                                           |
| **exchange_segment**    | Instrument/market/options tools                                              | Must be one of: `IDX_I`, `NSE_EQ`, `NSE_FNO`, `BSE_EQ`, `NSE_CURRENCY`, `MCX_COMM`, `BSE_CURRENCY`, `BSE_FNO`                                                    |
| **Dates**               | `from_date`, `to_date`, `expiry`                                             | `YYYY-MM-DD` for daily/history/expiry; `YYYY-MM-DD` or `YYYY-MM-DD HH:MM:SS` for intraday                                                                        |
| **to_date / from_date** | `get_trade_history`, `get_historical_daily_data`, `get_intraday_minute_data` | **to_date must be today.** **from_date must be the last trading day before to_date** (NSE/BSE calendar via `MarketCalendar`). Any other combination is rejected. |
| **interval**            | `get_intraday_minute_data`                                                   | One of: `1`, `5`, `15`, `25`, `60`                                                                                                                               |
| **page_number**         | `get_trade_history`                                                          | Non-negative integer                                                                                                                                             |

Implementation: `DhanMcp::ArgumentValidator` (see `app/services/dhan_mcp/argument_validator.rb`). Tools with no arguments (e.g. `get_holdings`) are not validated for extra keys.

## Protocol

All requests are JSON-RPC 2.0. To call a tool, use `method: "tools/call"` and pass `name` and `arguments` in `params`.

### Example: call a tool (no auth)

```bash
curl -s -X POST http://localhost:5002/mcp \
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

### Example: call a tool (with Bearer auth, when MCP_ACCESS_TOKEN is set)

```bash
curl -s -X POST https://your-app.example.com/mcp \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_MCP_ACCESS_TOKEN" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_holdings","arguments":{}}}'
```

Responses include `result.content[].text` (often markdown-wrapped JSON) or `error` on failure.

---

## Available tools

Tools use the app’s Dhan credentials (`CLIENT_ID`, `ACCESS_TOKEN`). When `MCP_ACCESS_TOKEN` is not set, no extra auth is required; when it is set (production), send `Authorization: Bearer <MCP_ACCESS_TOKEN>`.

### Portfolio & funds

| Tool                | Description                          | `arguments` |
| ------------------- | ------------------------------------ | ----------- |
| **get_holdings**    | Current portfolio holdings           | `{}`        |
| **get_positions**   | Open positions (intraday + delivery) | `{}`        |
| **get_fund_limits** | Available funds, margins, limits     | `{}`        |

### Orders & trades

| Tool                            | Description                        | `arguments`                                                                         |
| ------------------------------- | ---------------------------------- | ----------------------------------------------------------------------------------- |
| **get_order_list**              | All orders (today + history)       | `{}`                                                                                |
| **get_order_by_id**             | Order by Dhan order ID             | `{"order_id": "ORD123"}`                                                            |
| **get_order_by_correlation_id** | Order by your correlation ID       | `{"correlation_id": "my-ref-1"}`                                                    |
| **get_trade_book**              | Executed trades for an order       | `{"order_id": "ORD123"}`                                                            |
| **get_trade_history**           | Trades in a date range (paginated) | `{"from_date": "2025-01-01", "to_date": "2025-01-28"}` optional: `"page_number": 0` |

### Instruments & market data

| Tool                          | Description                            | `arguments`                                                                                                                                               |
| ----------------------------- | -------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **get_instrument**            | Resolve instrument by segment + symbol | `{"exchange_segment": "NSE_EQ", "symbol": "RELIANCE"}`                                                                                                    |
| **get_market_ohlc**           | Current OHLC for a symbol              | `{"exchange_segment": "NSE_EQ", "symbol": "RELIANCE"}`                                                                                                    |
| **get_historical_daily_data** | Daily candle data                      | `{"exchange_segment": "NSE_EQ", "symbol": "RELIANCE", "from_date": "2025-01-01", "to_date": "2025-01-28"}`                                                |
| **get_intraday_minute_data**  | Minute candle data                     | `{"exchange_segment": "NSE_EQ", "symbol": "RELIANCE", "from_date": "2025-01-28", "to_date": "2025-01-28"}` optional: `"interval": "1"` (1, 5, 15, 25, 60) |

### Options

| Tool                 | Description                                                                                                | `arguments`                                                                  |
| -------------------- | ---------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| **get_expiry_list**  | Expiry dates for an underlying (use underlying segment: IDX_I for indices, NSE_EQ for stocks; not NSE_FNO) | `{"exchange_segment": "IDX_I", "symbol": "NIFTY"}`                           |
| **get_option_chain** | Full option chain for an expiry                                                                            | `{"exchange_segment": "NSE_FNO", "symbol": "NIFTY", "expiry": "2025-01-30"}` |

### Other

| Tool                 | Description         | `arguments` |
| -------------------- | ------------------- | ----------- |
| **get_edis_inquiry** | eDIS inquiry status | `{}`        |

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
curl -s -X POST http://localhost:5002/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_holdings","arguments":{}}}'
```

### Market OHLC (RELIANCE)

```bash
curl -s -X POST http://localhost:5002/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_market_ohlc","arguments":{"exchange_segment":"NSE_EQ","symbol":"RELIANCE"}}}'
```

### NIFTY expiry list

```bash
curl -s -X POST http://localhost:5002/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_expiry_list","arguments":{"exchange_segment":"IDX_I","symbol":"NIFTY"}}}'
```

### Instrument (SENSEX)

```bash
curl -s -X POST http://localhost:5002/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_instrument","arguments":{"exchange_segment":"IDX_I","symbol":"SENSEX"}}}'
```

---

## Client configuration

This MCP is exposed as a **single HTTP POST endpoint** (JSON-RPC 2.0). Use the URL for your environment:

| Environment | URL                                                                    |
| ----------- | ---------------------------------------------------------------------- |
| Local       | `http://localhost:5002/mcp` (or your `PORT`)                           |
| Deployed    | Your app’s base URL + `/mcp` (e.g. `https://your-app.example.com/mcp`) |

Configure your client to use that URL as an **HTTP / Streamable HTTP** MCP server. For production, set `MCP_ACCESS_TOKEN` and send it as `Authorization: Bearer <token>` (see [Production](#production-authentication-and-limits)).

| Client             | Where to configure                                     | What to set                                   |
| ------------------ | ------------------------------------------------------ | --------------------------------------------- |
| **Cursor**         | `.cursor/mcp.json` or Settings → MCP                   | Server type **URL**, value = URL above        |
| **Claude Desktop** | Settings → Connectors, or `claude_desktop_config.json` | MCP connector with **Server URL** = URL above |
| **Windsurf**       | Settings → MCP                                         | Add server, type **HTTP/URL**, URL = above    |
| **Others**         | MCP / Connectors / Integrations                        | Add HTTP MCP server with URL above            |

### Cursor

1. **Project-level**
   Edit or create `.cursor/mcp.json` in the project root:

   ```json
   {
     "mcpServers": {
       "dhan": {
         "url": "http://localhost:5002/mcp"
       }
     }
   }
   ```

   For a deployed app, set `"url"` to your app’s base URL + `/mcp`. If the server requires auth, configure your client to send `Authorization: Bearer <MCP_ACCESS_TOKEN>` (Cursor may support headers or env in MCP config; store the token in env and reference it in the header).

2. **App settings**
   Or add the server in **Cursor Settings → MCP**: create a new server, choose **URL** as the type, and set the URL above.

3. Restart Cursor or reload the window so it picks up the new server. The Dhan tools should appear when the MCP is enabled.

### Claude Desktop

Claude supports **remote HTTP MCP servers** via Connectors (Streamable HTTP).

1. **Settings → Connectors** (or **Features → Build**)
   Add a new connector and choose **Model Context Protocol (MCP)**.

2. **Server URL**
   Set the MCP endpoint (e.g. `http://localhost:5002/mcp` for local, or your deployed app URL + `/mcp`).

3. **Auth**
   If you set `MCP_ACCESS_TOKEN` in production, set the connector auth to **Bearer** with that token; otherwise leave auth empty.

4. Save and enable the connector. Remote MCP/Connectors are available on **Pro, Max, Team, and Enterprise** plans.

**Manual config (if your build uses a config file):**
Edit the Claude Desktop config and add under `mcpServers`: `"dhan": { "url": "http://localhost:5002/mcp" }` (or your deployed URL + `/mcp`). File locations:

- **macOS**: `~/Library/Application Support/Claude/claude_desktop_config.json`
- **Windows**: `%APPDATA%\Claude\claude_desktop_config.json`
- **Linux**: `~/.config/Claude/claude_desktop_config.json`

### Windsurf (Codeium)

1. Open **Settings → MCP** (or equivalent).
2. Add an MCP server with **URL** / **HTTP** type.
3. URL: your MCP endpoint (e.g. `http://localhost:5002/mcp` or your deployed app URL + `/mcp`).

### Other clients (Continue, MCP explorers, etc.)

Any client that supports **MCP over HTTP** (Streamable HTTP / JSON-RPC POST to one URL) can use this server:

1. Add a new MCP server / connection.
2. Set transport to **HTTP** or **URL**.
3. Set the server URL (e.g. `http://localhost:5002/mcp` or your deployed app URL + `/mcp`).
4. When `MCP_ACCESS_TOKEN` is set, send `Authorization: Bearer <token>`; otherwise no auth is required.

If the client asks for **SSE** or **Streamable HTTP**, use the same URL; this endpoint accepts JSON-RPC `POST` and returns JSON.

---

## Implementation notes

- **Controller**: `McpController#index` — enforces optional Bearer auth when `MCP_ACCESS_TOKEN` is set, rejects oversized body (1 MB limit), returns 400 when body is blank, otherwise forwards to the MCP server.
- **Service**: `DhanMcpService` — builds the `MCP::Server`, defines all tools, and uses the DhanHQ gem under the hood. Each tool that takes arguments runs `DhanMcp::ArgumentValidator.validate(tool_name, args)` before calling Dhan; invalid args return an error string in the usual `Error: …` format.
- **Validator**: `DhanMcp::ArgumentValidator` — validates required/optional args, `exchange_segment` enum, date formats, `interval`, and `page_number`. Returns `nil` if valid, or a short error message string.
- **Config**: `config/initializers/dhan_mcp.rb` — builds the server at boot and stores it in `Rails.application.config.x.dhan_mcp_server`.
- **Route**: `POST /mcp` → `mcp#index`.

All tools are read-only; no orders or modifications are performed via the MCP.

**Running MCP specs:** `bundle exec rspec --tag mcp`
