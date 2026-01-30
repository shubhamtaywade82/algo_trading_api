#!/usr/bin/env bash
# Test the POST /mcp endpoint (JSON-RPC 2.0).
# Usage: ./script/test_mcp.sh [base_url]
# Example: ./script/test_mcp.sh http://localhost:3000
# Requires the Rails server to be running.

set -e
BASE_URL="${1:-http://localhost:3000}"
MCP_URL="${BASE_URL}/mcp"

echo "Testing MCP at ${MCP_URL}"
echo ""

# 1. Empty body -> 400, parse error
echo "1. Empty body (expect 400, Parse error)..."
resp=$(curl -s -w "\n%{http_code}" -X POST "${MCP_URL}" -H "Content-Type: application/json" -d "")
code=$(echo "$resp" | tail -n1)
body=$(echo "$resp" | sed '$d')
if [ "$code" = "400" ] && echo "$body" | grep -q '"code":-32700' && echo "$body" | grep -q 'Parse error'; then
  echo "   OK (400, parse error)"
else
  echo "   FAIL (got HTTP $code, body: $body)"
  exit 1
fi

# 2. tools/list -> 200, jsonrpc 2.0
echo "2. tools/list (expect 200, jsonrpc 2.0)..."
resp=$(curl -s -w "\n%{http_code}" -X POST "${MCP_URL}" -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}')
code=$(echo "$resp" | tail -n1)
body=$(echo "$resp" | sed '$d')
if [ "$code" = "200" ] && echo "$body" | grep -q '"jsonrpc":"2.0"'; then
  echo "   OK (200, jsonrpc 2.0)"
else
  echo "   FAIL (got HTTP $code)"
  echo "$body" | head -c 200
  echo "..."
  exit 1
fi

# 3. tools/call get_instrument (no Dhan creds needed for validation; may return error from server)
echo "3. tools/call get_instrument IDX_I SENSEX (expect 200)..."
resp=$(curl -s -w "\n%{http_code}" -X POST "${MCP_URL}" -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_instrument","arguments":{"exchange_segment":"IDX_I","symbol":"SENSEX"}}}')
code=$(echo "$resp" | tail -n1)
body=$(echo "$resp" | sed '$d')
if [ "$code" = "200" ] && echo "$body" | grep -q '"jsonrpc":"2.0"'; then
  echo "   OK (200, valid JSON-RPC response)"
else
  echo "   FAIL (got HTTP $code)"
  echo "$body" | head -c 300
  echo "..."
  exit 1
fi

echo ""
echo "All MCP checks passed."
