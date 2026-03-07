#!/usr/bin/env bash
# Test the POST /mcp endpoint (JSON-RPC 2.0, Streamable HTTP).
# Usage: ./script/test_mcp.sh [base_url]
# Example: ./script/test_mcp.sh http://localhost:5002
# Requires the Rails server to be running.
# Requires MCP_ACCESS_TOKEN (set in .env or export). Script sources .env from project root if present.
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

# Streamable HTTP: Accept: application/json, text/event-stream
echo "Testing MCP at ${MCP_URL}"
echo ""

# 1. Empty body -> 400, parse error
echo "1. Empty body (expect 400, Parse error)..."
resp=$(curl -s -w "\n%{http_code}" -X POST "${MCP_URL}" -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" -H "${MCP_AUTH_HEADER}" -d "")
code=$(echo "$resp" | tail -n1)
body=$(echo "$resp" | sed '$d')
if [ "$code" = "400" ] && (echo "$body" | grep -q '"code":-32700' && echo "$body" | grep -q 'Parse error' || echo "$body" | grep -q 'Invalid JSON'); then
  echo "   OK (400, parse error)"
else
  echo "   FAIL (got HTTP $code, body: $body)"
  exit 1
fi

# 2. tools/list -> 200, jsonrpc 2.0
echo "2. tools/list (expect 200, jsonrpc 2.0)..."
resp=$(curl -s -w "\n%{http_code}" -X POST "${MCP_URL}" -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" -H "${MCP_AUTH_HEADER}" -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}')
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
resp=$(curl -s -w "\n%{http_code}" -X POST "${MCP_URL}" -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" -H "${MCP_AUTH_HEADER}" -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_instrument","arguments":{"exchange_segment":"IDX_I","symbol":"SENSEX"}}}')
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
