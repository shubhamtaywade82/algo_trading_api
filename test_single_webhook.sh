#!/bin/bash

# Single Webhook Test Script
# Usage: ./test_single_webhook.sh <balance> <ticker> <signal_type>

BASE_URL="http://localhost:5002"
WEBHOOK_ENDPOINT="/webhooks/tradingview"

BALANCE=${1:-100000}
TICKER=${2:-"NIFTY"}
SIGNAL_TYPE=${3:-"long_entry"}

# Set prices and exchange based on ticker
case $TICKER in
  "NIFTY")
    PRICE=22900.9
    EXCHANGE="NSE"
    ;;
  "BANKNIFTY")
    PRICE=48500.2
    EXCHANGE="NSE"
    ;;
  "SENSEX")
    PRICE=72500.3
    EXCHANGE="BSE"
    ;;
  *)
    PRICE=22900.9
    EXCHANGE="NSE"
    ;;
esac

# Set action based on signal type
case $SIGNAL_TYPE in
  "long_entry")
    ACTION="buy"
    POSITION="flat"
    ;;
  "long_exit")
    ACTION="sell"
    POSITION="long"
    ;;
  "short_entry")
    ACTION="sell"
    POSITION="flat"
    ;;
  "short_exit")
    ACTION="buy"
    POSITION="short"
    ;;
  *)
    ACTION="buy"
    POSITION="flat"
    ;;
esac

echo "🚀 Testing Single Webhook"
echo "========================="
echo "💰 Available Balance: ₹$BALANCE"
echo "📈 Ticker: $TICKER"
echo "📊 Signal: $SIGNAL_TYPE"
echo "💵 Price: ₹$PRICE"
echo ""

PAYLOAD='{
  "alert": {
    "ticker": "'$TICKER'",
    "instrument_type": "index",
    "action": "'$ACTION'",
    "order_type": "market",
    "current_position": "'$POSITION'",
    "strategy_type": "intraday",
    "current_price": '$PRICE',
    "time": "'$(date -u +%Y-%m-%dT%H:%M:%S.000Z)'",
    "chart_interval": "1",
    "signal_type": "'$SIGNAL_TYPE'",
    "strategy_name": "Enhanced AlgoTrading Alerts",
    "strategy_id": "'$TICKER'_intraday",
    "exchange": "'$EXCHANGE'"
  }
}'

echo "📤 Sending webhook..."
echo ""

response=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -H "X-Available-Balance: $BALANCE" \
    -d "$PAYLOAD" \
    "$BASE_URL$WEBHOOK_ENDPOINT")

http_code=$(echo "$response" | grep "HTTP_CODE:" | cut -d: -f2)
body=$(echo "$response" | sed '/HTTP_CODE:/d')

echo "📥 Response (HTTP $http_code):"
echo "$body" | jq . 2>/dev/null || echo "$body"

echo ""
echo "💡 Expected Capital Band for ₹$BALANCE:"
if [ $BALANCE -le 75000 ]; then
    echo "   📊 Band: ₹50K → 30% allocation, 5% risk per trade"
elif [ $BALANCE -le 150000 ]; then
    echo "   📊 Band: ₹1L → 25% allocation, 3.5% risk per trade"
elif [ $BALANCE -le 300000 ]; then
    echo "   📊 Band: ₹2L-3L → 20% allocation, 3% risk per trade"
else
    echo "   📊 Band: ₹3L+ → 20% allocation, 2.5% risk per trade"
fi
