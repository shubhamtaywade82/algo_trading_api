# MCP (Model Context Protocol) — Algo Trading API

The app exposes a **spec-compliant** MCP server over HTTP so agents (Claude Desktop, Cursor, Codex CLI, Ollama, etc.) can discover and call trading tools via JSON-RPC 2.0.

## Lifecycle and capabilities

The server implements the required MCP layers: **initialize** (protocolVersion, capabilities, serverInfo), **notifications/initialized**, **tools/list**, and **tools/call**. See [Protocol](#protocol) below.

## Endpoint

| Environment  | URL                                                   |
| ------------ | ----------------------------------------------------- |
| **Local**    | `http://localhost:5002/mcp` (or `PORT` from `.env`)   |
| **Deployed** | `https://YOUR_APP_HOST/mcp` (use your app’s base URL) |

- **Method**: `POST` only. `GET` returns **405** Method Not Allowed.
- **Content-Type**: `application/json`
- **Body**: JSON-RPC 2.0 request (`method`, `params`, `id` for requests; omit `id` for notifications).

Empty or invalid JSON body returns **400** with a JSON-RPC parse error.

### Production: authentication and limits

- **Authentication** — `MCP_ACCESS_TOKEN` is **required**. Set it in the environment; the server rejects every request with **401** Unauthorized when the `Authorization: Bearer <token>` header is missing or does not match. If `MCP_ACCESS_TOKEN` is not set at all, the server returns **503** Service Unavailable with data `MCP_ACCESS_TOKEN must be set`.
- **Request body size** — Requests with `Content-Length` greater than 1 MB are rejected with **413** (Payload Too Large) and a JSON-RPC error.

Set `MCP_ACCESS_TOKEN` in your environment (e.g. `.env` for local, Render dashboard → Environment for production) and configure every client to send the same value as a Bearer token. Use a long, random secret (e.g. `openssl rand -hex 32`).

## Protocol

1. **initialize** — `method: "initialize"`. Response: `result.protocolVersion`, `result.capabilities` (tools.listChanged: false), `result.serverInfo` (name: algo-trading-api).
2. **notifications/initialized** — Optional; no `id`; server returns 200 with empty body.
3. **tools/list** — `method: "tools/list"`. Response: `result.tools` (array of name, title, description, inputSchema).
4. **tools/call** — `method: "tools/call"`, `params.name`, `params.arguments`. Response: `result.content[]` (type: "text", text: JSON string), `result.isError`.

For best compatibility with ChatGPT Actions / imported OpenAPI schemas, send tool calls in the canonical `params` envelope shown in the examples. The server also accepts a compatibility shim where some clients place the same payload under a top-level `arguments` key, but `params` is the documented format.

## Available tools (8 trading tools)

### Example: call a tool (no auth)

```bash
curl -s -X POST http://localhost:5002/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
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
  -H "Accept: application/json, text/event-stream" \
  -H "Authorization: Bearer YOUR_MCP_ACCESS_TOKEN" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_holdings","arguments":{}}}'
```

Responses include `result.content[].text` (often markdown-wrapped JSON) or `error` on failure.

---

## Available tools

Tools use the app’s Dhan credentials (`CLIENT_ID`, `ACCESS_TOKEN`). **Every request must include** `Authorization: Bearer <MCP_ACCESS_TOKEN>`; see [Production: authentication and limits](#production-authentication-and-limits).

## Available tools (8 trading tools)

Every request must include `Authorization: Bearer <MCP_ACCESS_TOKEN>`. See [Production: authentication and limits](#production-authentication-and-limits).

| Tool                | Purpose                        | Key arguments |
| ------------------- | ------------------------------ | ------------- |
| **get_option_chain**  | Retrieve analyzed option chain | `index` (e.g. NIFTY), optional `expiry` |
| **scan_trade_setup**  | Run strategy scanner           | `index_symbol`, optional `expiry_date`, `strategy_type`, `instrument_type` |
| **place_trade**       | Execute trade                  | `security_id`, `exchange_segment`, `transaction_type`, `quantity`, `product_type`, optional `order_type`, `price` |
| **close_trade**       | Close position                 | `security_id`, `exchange_segment`, `net_quantity`, `product_type` |
| **get_positions**     | Active positions               | (none) |
| **get_market_data**   | LTP / OHLC                     | `exchange_segment`, `symbol` |
| **backtest_strategy** | Run historical test            | Optional `symbol`, `from_date`, `to_date` (stub: returns not_implemented) |
| **explain_trade**     | AI explanation                 | `query`, optional `context` |

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

Configure your client to use that URL as an **HTTP / Streamable HTTP** MCP server. Set `MCP_ACCESS_TOKEN` in the app environment and send it as `Authorization: Bearer <token>` (see [Production](#production-authentication-and-limits)).

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
   If you set `MCP_ACCESS_TOKEN` in the app environment, set the connector auth to **Bearer** with that token (required for this app).

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
4. When calling the MCP endpoint, send `Authorization: Bearer <MCP_ACCESS_TOKEN>` (required).

If the client asks for **SSE** or **Streamable HTTP**, use the same URL; this endpoint accepts JSON-RPC `POST` and returns JSON.

---

## Implementation notes

- **Controller**: `McpController#handle` — requires `MCP_ACCESS_TOKEN`; validates `Authorization: Bearer <token>`; rejects oversized body (1 MB); parses JSON and dispatches to `Mcp::Dispatcher`.
- **Dispatcher**: `Mcp::Dispatcher` — routes `initialize`, `notifications/initialized`, `tools/list`, `tools/call`.
- **Handlers**: `Mcp::Handlers::Initialize`, `ListTools`, `CallTool` — lifecycle, tool list, and tool execution.
- **Tool registry**: `Mcp::ToolRegistry` — orchestrates tool classes in `app/services/mcp/tools/`.
- **DhanHQ Modular Tools**: The app also contains a modular MCP implementation in `app/services/dhan_mcp/` (Portfolio, Order, Market, Account tools) used for raw broker access via the `mcp` gem.
- **Route**: `POST /mcp` → `mcp#handle`; `GET /mcp` → 405.

**Running MCP specs:** `bundle exec rspec spec/requests/mcp_spec.rb` (requires local or allowed test DB; see DatabaseCleaner safeguard if using remote DATABASE_URL).
