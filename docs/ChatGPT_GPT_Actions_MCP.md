# ChatGPT Custom GPT (Actions) using Algo Trading MCP

This guide shows how to let a **ChatGPT Custom GPT** call your app’s **MCP server** (JSON-RPC over HTTP).

Your server endpoints:
- Production MCP: `POST /mcp`
- Debug MCP (optional): `POST /mcp/debug`

The MCP method you call is always the same:
- `method: "tools/list"` (discover tools)
- `method: "tools/call"` (execute a tool by name)

This works because ChatGPT “Actions” can call arbitrary HTTP `POST` endpoints with JSON bodies.

See also: `docs/MCP.md`.

---

## 1) Prerequisites

1. Your Rails API must be running and reachable.
   - Local: `http://localhost:<PORT>/mcp`
   - Deployed: `https://YOUR_HOST/mcp`
2. Set `MCP_ACCESS_TOKEN` in the app environment (required).
3. (For debug tools only) set `MCP_DEBUG_TOKEN` (optional). If it’s not set, debug auth falls back to `MCP_ACCESS_TOKEN`.

---

## 2) Auth in ChatGPT Actions

Your MCP server expects:
- HTTP header: `Authorization: Bearer <MCP_ACCESS_TOKEN>`

In the ChatGPT Actions configuration:
- Create an API key / bearer token named anything you like (example below: `MCP_ACCESS_TOKEN`).
- In the Actions request header, set:
  - `Authorization: Bearer {{MCP_ACCESS_TOKEN}}`

---

## 3) Define Actions (recommended OpenAPI shape)

Create **one generic action** that calls MCP `tools/call`.

### Action A: `mcp_tools_call` (generic)

**HTTP**
- `POST <YOUR_BASE_URL>/mcp`

**Request body**
Pass the MCP JSON-RPC fields straight through.

Example JSON body you will send from the GPT Action:
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "analyze_trade",
    "arguments": { "symbol": "NIFTY" }
  }
}
```

**Response**
Your MCP server returns (at least):
- `result.structuredContent` (machine-friendly structured data)
- `result.content[0].text` (text version)
- `result.isError` (boolean)

### (Optional) Action B: `mcp_tools_list`

Use this action to discover available tools:
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/list",
  "params": {}
}
```

---

## 4) Tool usage contract (production toolset)

On `/mcp` your server exposes the production tools (current set includes):
- `analyze_trade`
- `place_order`
- `get_positions`
- `manage_position`
- `exit_position`
- `system_status`
- `get_market_sentiment`
- `get_confluence_signal`
- `get_key_levels`
- `get_iv_rank`

On `/mcp/debug` you have the original debug-only tools (hidden from the main GPT workflow by default).

---

## 5) Example: GPT trade workflow (analysis -> optional execution)

### Step 1: Analyze

Call:
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/call",
  "params": {
    "name": "analyze_trade",
    "arguments": { "symbol": "NIFTY", "expiry": "YYYY-MM-DD" }
  }
}
```

Interpretation:
- If `structuredContent.proceed == false`, explain `structuredContent.reason` and stop.
- If `structuredContent.proceed == true`, you have:
  - `direction` (CE/PE)
  - `expiry`
  - `iv_rank`
  - `selected_strike` (strike + greeks/metrics; exact shape comes from option analysis)

### Step 2: Gate with system status

Call:
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "tools/call",
  "params": { "name": "system_status", "arguments": {} }
}
```

Interpretation:
- Only proceed to `place_order` if `structuredContent.allowed_to_trade == true`

### Step 3: Place order (only if you have required broker identifiers)

Your production `place_order` tool currently requires:
- `security_id`
- `exchange_segment`
- `transaction_type` (BUY/SELL)
- `quantity`
- `product_type` (INTRADAY/MARGIN/CNC)
- `order_type` (MARKET/LIMIT)
- `price` (required for LIMIT)

Important limitation:
- `analyze_trade` returns strike-level information, but **not** `security_id`.
- To call `place_order`, your GPT must either:
  1. Be provided `security_id` from your UI/policy layer (you can store a strike->security_id map), OR
  2. You extend your MCP toolset with a new production tool like `resolve_derivative` that maps `(symbol, expiry, strike, option_type)` to `(security_id, exchange_segment)`.

Example call (placeholder values):
```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "method": "tools/call",
  "params": {
    "name": "place_order",
    "arguments": {
      "security_id": "12345",
      "exchange_segment": "NSE_FNO",
      "transaction_type": "BUY",
      "quantity": 75,
      "product_type": "INTRADAY",
      "order_type": "MARKET"
    }
  }
}
```

---

## 6) GPT Instructions (paste into Custom GPT “Instructions”)

Use this as a starting point for the GPT’s system prompt/instructions:

```text
You are a trading assistant for Indian index options.

Use the available MCP tools via Actions.

Workflow:
1) For requests like "analyze trade for NIFTY/BANKNIFTY/SENSEX", call `analyze_trade`.
2) If `analyze_trade.proceed` is false, respond with the reason from `analyze_trade.reason` and do not place any orders.
3) If proceed is true, call `system_status`.
4) Only place orders if `system_status.allowed_to_trade` is true.

Execution constraints:
- Do NOT call `place_order` unless required broker identifiers are provided:
  security_id, exchange_segment, quantity, product_type, order_type (+ price if LIMIT).
- If security_id is missing, explain what’s missing and ask for it (or instruct the user that execution cannot proceed).
```

---

## 7) Debug mode (optional)

If you want the GPT to use debug-only tools, create a second action that targets:
- `POST /mcp/debug`

Authenticate with `MCP_DEBUG_TOKEN` (preferred) or fall back to `MCP_ACCESS_TOKEN`.

---

## 8) Next improvements (optional, but recommended)

To make execution fully automatic from `analyze_trade`, add a production tool:
- `resolve_derivative(symbol, expiry, strike, option_type)` -> `{security_id, exchange_segment, lot_size}`

That would remove the current “strike-level vs security_id” gap and let ChatGPT place orders deterministically.

mcpPost maps to POST `/mcp` on your server.
  Since you can’t execute the call from here, use one of these ready-to-run requests.


  1) List available tools (`tools/list`)


  curl -s https://algo-trading-api.onrender.com/mcp \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -H "Authorization: Bearer $MCP_ACCESS_TOKEN" \
    -d '{
      "jsonrpc":"2.0",
      "id":1,
      "method":"tools/list",
      "params":{}
    }'



  2) Analyze a trade (`tools/call` -> `analyze_trade`)

  This is a generic deterministic proposal (no order execution).

  curl -s https://algo-trading-api.onrender.com/mcp \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -H "Authorization: Bearer $MCP_ACCESS_TOKEN" \
    -d '{
      "jsonrpc":"2.0",
      "id":2,
      "method":"tools/call",
      "params":{
        "name":"analyze_trade",
        "arguments":{
          "symbol":"NIFTY",
          "expiry":"2026-03-27"
        }
      }
    }'

  If you tell me which tool you want to call next (e.g. system_status, place_order, etc.) and the required arguments (especially security_id
  for place_order), I’ll generate the exact request body for it.


  Call the algo-trading-api.onrender.com API with the mcpDebugPost operation
  Stopped talking to App
  [debug] Calling HTTP endpoint
  [debug] Response received
  [debug] Calling HTTP endpoint…


  Your mcpDebugPost call reached the server, but the server rejected auth because it couldn’t find a valid debug token.
  For /mcp/debug the controller uses this precedence:
  • MCP_DEBUG_TOKEN (preferred)
  • else fallback to MCP_ACCESS_TOKEN

  So you need one of these to be set in the Render app:
  • MCP_DEBUG_TOKEN = some secret
  • or ensure MCP_ACCESS_TOKEN is set and you’re sending that in the header



  Retry request body (correct operation)

  /mcp/debug is still POST /mcp/debug and the JSON-RPC body is the same MCP format.
  Example: tools/list

  curl -s https://algo-trading-api.onrender.com/mcp/debug \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -H "Authorization: Bearer $MCP_DEBUG_TOKEN" \
    -d '{
      "jsonrpc":"2.0",
      "id":1,
      "method":"tools/list",
      "params":{}
    }'



  Why you got the error

  The server returned: Unauthorized — Invalid or missing debug access token, which means either:
  • the environment variable MCP_DEBUG_TOKEN is empty AND you didn’t set/use the fallback, or
  • the token you sent in Authorization: Bearer ... doesn’t match what the app expects.

  If you tell me which token value you set in Render (or confirm whether you only set MCP_ACCESS_TOKEN), I’ll generate the exact curl for the
  right header and the specific debug tool you want to call.