#!/usr/bin/env bash
# Call each MCP tool and check for 200 + JSON-RPC 2.0 response.
# Usage: ./script/test_mcp_tools.sh [base_url]
# Example: ./script/test_mcp_tools.sh http://localhost:5002
# Set TO_DATE / FROM_DATE for date-range tools (default: today / yesterday in local TZ).
# Set SHOW_RESPONSE=1 to print a short preview of each response (default: 1). Set to 0 to hide.
# Tools that need Dhan credentials may return "Error: ..." in result; we only check HTTP 200 + jsonrpc.

set -e
BASE_URL="${1:-http://localhost:3000}"
MCP_URL="${BASE_URL}/mcp"

# Dates for get_trade_history, get_historical_daily_data, get_intraday_minute_data
# App requires to_date=today and from_date=last_trading_day; if wrong, result may contain validation error.
if [ -n "$TO_DATE" ]; then
  TO_D="$TO_DATE"
else
  TO_D=$(date +%Y-%m-%d)
fi
if [ -n "$FROM_DATE" ]; then
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

# Expiry for get_option_chain: fetch next expiry from get_expiry_list unless EXPIRY is set.
# Use underlying segment: IDX_I for indices (NIFTY, SENSEX), NSE_EQ for stocks (not derivative NSE_FNO).
EXPIRY_SYMBOL="${EXPIRY_SYMBOL:-NIFTY}"
EXPIRY_SEGMENT="${EXPIRY_SEGMENT:-IDX_I}"
if [ -z "$EXPIRY" ]; then
  expiry_resp=$(curl -s -X POST "${MCP_URL}" -H "Content-Type: application/json" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":0,\"method\":\"tools/call\",\"params\":{\"name\":\"get_expiry_list\",\"arguments\":{\"exchange_segment\":\"$EXPIRY_SEGMENT\",\"symbol\":\"$EXPIRY_SYMBOL\"}}}")
  if command -v jq >/dev/null 2>&1; then
    raw=$(echo "$expiry_resp" | jq -r '.result.content[0].text // empty')
    if [ -n "$raw" ]; then
      # Strip markdown code fence (first line ```json, last line ```)
      json_part=$(echo "$raw" | sed '1d;$d')
      next_expiry=$(echo "$json_part" | jq -r 'if type == "array" then .[0] elif .expiry then .expiry[0] elif .expiries then .expiries[0] else . end' 2>/dev/null)
      if [ -n "$next_expiry" ] && [ "$next_expiry" != "null" ]; then
        EXPIRY="$next_expiry"
      fi
    fi
  fi
  EXPIRY="${EXPIRY:-2025-02-27}"
fi

SHOW_RESPONSE="${SHOW_RESPONSE:-1}"
PREVIEW_LEN="${PREVIEW_LEN:-380}"

run_tool() {
  local name="$1"
  local body="$2"
  local resp code body_only
  resp=$(curl -s -w "\n%{http_code}" -X POST "${MCP_URL}" -H "Content-Type: application/json" -d "$body")
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
echo "  (TO_DATE=$TO_D, FROM_DATE=$FROM_D, EXPIRY=$EXPIRY)"
echo ""

failed=0

# No-arg tools
run_tool "get_holdings" '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_holdings","arguments":{}}}' || ((failed++))
run_tool "get_positions" '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_positions","arguments":{}}}' || ((failed++))
run_tool "get_fund_limits" '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_fund_limits","arguments":{}}}' || ((failed++))
run_tool "get_order_list" '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"get_order_list","arguments":{}}}' || ((failed++))
run_tool "get_edis_inquiry" '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"get_edis_inquiry","arguments":{}}}' || ((failed++))

# Order/trade tools (need valid IDs for real data; we only check dispatch)
run_tool "get_order_by_id" '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"get_order_by_id","arguments":{"order_id":"test-order-123"}}}' || ((failed++))
run_tool "get_order_by_correlation_id" '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"get_order_by_correlation_id","arguments":{"correlation_id":"test-corr-1"}}}' || ((failed++))
run_tool "get_trade_book" '{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"get_trade_book","arguments":{"order_id":"test-order-123"}}}' || ((failed++))
run_tool "get_trade_history" "{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"tools/call\",\"params\":{\"name\":\"get_trade_history\",\"arguments\":{\"from_date\":\"$FROM_D\",\"to_date\":\"$TO_D\"}}}" || ((failed++))

# Instrument / market (no Dhan needed for instrument lookup in many cases)
run_tool "get_instrument" '{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"get_instrument","arguments":{"exchange_segment":"IDX_I","symbol":"SENSEX"}}}' || ((failed++))
run_tool "get_instrument NIFTY" '{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"get_instrument","arguments":{"exchange_segment":"IDX_I","symbol":"NIFTY"}}}' || ((failed++))
run_tool "get_market_ohlc" '{"jsonrpc":"2.0","id":12,"method":"tools/call","params":{"name":"get_market_ohlc","arguments":{"exchange_segment":"NSE_EQ","symbol":"RELIANCE"}}}' || ((failed++))
run_tool "get_expiry_list" '{"jsonrpc":"2.0","id":13,"method":"tools/call","params":{"name":"get_expiry_list","arguments":{"exchange_segment":"IDX_I","symbol":"NIFTY"}}}' || ((failed++))
run_tool "get_option_chain" "{\"jsonrpc\":\"2.0\",\"id\":14,\"method\":\"tools/call\",\"params\":{\"name\":\"get_option_chain\",\"arguments\":{\"exchange_segment\":\"NSE_FNO\",\"symbol\":\"NIFTY\",\"expiry\":\"$EXPIRY\"}}}" || ((failed++))

# Date-range tools (may return validation error if TO_DATE/FROM_DATE don't match app calendar)
run_tool "get_historical_daily_data" "{\"jsonrpc\":\"2.0\",\"id\":15,\"method\":\"tools/call\",\"params\":{\"name\":\"get_historical_daily_data\",\"arguments\":{\"exchange_segment\":\"NSE_EQ\",\"symbol\":\"RELIANCE\",\"from_date\":\"$FROM_D\",\"to_date\":\"$TO_D\"}}}" || ((failed++))
run_tool "get_intraday_minute_data" "{\"jsonrpc\":\"2.0\",\"id\":16,\"method\":\"tools/call\",\"params\":{\"name\":\"get_intraday_minute_data\",\"arguments\":{\"exchange_segment\":\"NSE_EQ\",\"symbol\":\"RELIANCE\",\"from_date\":\"$FROM_D\",\"to_date\":\"$TO_D\"}}}" || ((failed++))

echo ""
if [ "$failed" -eq 0 ]; then
  echo "All tools returned 200 + JSON-RPC 2.0."
else
  echo "$failed tool(s) failed."
  exit 1
fi
