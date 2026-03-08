#!/usr/bin/env bash
# Call each MCP tool and check for 200 + JSON-RPC 2.0 response.
# Usage: ./script/test_mcp_tools.sh [base_url]
# Example: ./script/test_mcp_tools.sh http://localhost:5002
# Requires MCP_ACCESS_TOKEN (set in .env or export). Script sources .env from project root if present.
# Set TO_DATE / FROM_DATE for date-range tools. Set EXPIRY for get_option_chain/scan_trade_setup (optional).
# Set SHOW_RESPONSE=1 to print a short preview of each response (default: 1). Set to 0 to hide.
# Tools that need Dhan/OpenAI may return error in result; we only check HTTP 200 + jsonrpc.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
if [ -z "${MCP_ACCESS_TOKEN:-}" ] && [ -f "${ROOT_DIR}/.env" ]; then
  set -a
  # shellcheck source=/dev/null
  source "${ROOT_DIR}/.env"
  set +a
fi
if [ -z "${MCP_ACCESS_TOKEN:-}" ]; then
  echo "MCP_ACCESS_TOKEN is not set. Set it in .env or export it before running this script."
  exit 1
fi
BASE_URL="${1:-http://localhost:5002}"
MCP_URL="${BASE_URL}/mcp"
MCP_AUTH_HEADER="Authorization: Bearer ${MCP_ACCESS_TOKEN}"

if [ -n "${TO_DATE:-}" ]; then
  TO_D="$TO_DATE"
else
  TO_D=$(date +%Y-%m-%d)
fi
if [ -n "${FROM_DATE:-}" ]; then
  FROM_D="$FROM_DATE"
else
  if FROM_D=$(date -d "yesterday" +%Y-%m-%d 2>/dev/null); then
    :
  elif FROM_D=$(date -v-1d +%Y-%m-%d 2>/dev/null); then
    :
  else
    FROM_D="2025-01-28"
  fi
fi
EXPIRY="${EXPIRY:-}"

SHOW_RESPONSE="${SHOW_RESPONSE:-1}"
PREVIEW_LEN="${PREVIEW_LEN:-380}"

run_tool() {
  local name="$1"
  local body="$2"
  local resp code body_only
  resp=$(curl -s -w "\n%{http_code}" -X POST "${MCP_URL}" -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" -H "${MCP_AUTH_HEADER}" -d "$body")
  code=$(echo "$resp" | tail -n1)
  body_only=$(echo "$resp" | sed '$d')
  if [ "$code" = "200" ] && echo "$body_only" | grep -q '"jsonrpc":"2.0"'; then
    echo "  OK   $name"
    if [ "$SHOW_RESPONSE" = "1" ] || [ "$SHOW_RESPONSE" = "yes" ]; then
      echo "$body_only" | head -c "$PREVIEW_LEN" | sed 's/^/    /'
      [ "$(echo -n "$body_only" | wc -c)" -gt "$PREVIEW_LEN" ] && echo "    ..."
      echo ""
    fi
    return 0
  else
    echo "  FAIL $name (HTTP $code)"
    echo "$body_only" | head -c 200
    echo ""
    return 1
  fi
}

echo "Testing MCP tools at ${MCP_URL}"
echo "  (TO_DATE=$TO_D, FROM_DATE=$FROM_D, EXPIRY=${EXPIRY:-default})"
echo ""

failed=0

# 8 MCP tools
run_tool "get_positions" '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_positions","arguments":{}}}' || ((failed++))
run_tool "get_market_data" '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_market_data","arguments":{"exchange_segment":"IDX_I","symbol":"NIFTY"}}}' || ((failed++))

if [ -n "$EXPIRY" ]; then
  run_tool "get_option_chain" "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"get_option_chain\",\"arguments\":{\"index\":\"NIFTY\",\"expiry\":\"$EXPIRY\"}}}}" || ((failed++))
  run_tool "scan_trade_setup" "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"scan_trade_setup\",\"arguments\":{\"index_symbol\":\"NIFTY\",\"expiry_date\":\"$EXPIRY\",\"strategy_type\":\"intraday\"}}}}" || ((failed++))
else
  run_tool "get_option_chain" '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_option_chain","arguments":{"index":"NIFTY"}}}' || ((failed++))
  run_tool "scan_trade_setup" '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"scan_trade_setup","arguments":{"index_symbol":"NIFTY","strategy_type":"intraday"}}}' || ((failed++))
fi

run_tool "backtest_strategy" "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/call\",\"params\":{\"name\":\"backtest_strategy\",\"arguments\":{\"symbol\":\"NIFTY\",\"from_date\":\"$FROM_D\",\"to_date\":\"$TO_D\"}}}}" || ((failed++))
run_tool "explain_trade" '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"explain_trade","arguments":{"query":"What is a covered call?"}}}' || ((failed++))
run_tool "place_trade (dry-run)" '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"place_trade","arguments":{"security_id":"1","exchange_segment":"NSE_EQ","transaction_type":"BUY","quantity":1,"product_type":"CNC"}}}' || ((failed++))
run_tool "close_trade (dry-run)" '{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"close_trade","arguments":{"security_id":"1","exchange_segment":"NSE_EQ","net_quantity":1,"product_type":"CNC"}}}' || ((failed++))

echo ""
if [ "$failed" -eq 0 ]; then
  echo "All tools returned 200 + JSON-RPC 2.0."
else
  echo "$failed tool(s) failed."
  exit 1
fi
