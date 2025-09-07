#!/bin/bash

# Focused Webhook Test Script - Testing Capital-Aware Sizing
# Only testing NIFTY and BANKNIFTY (SENSEX not in database)

BASE_URL="http://localhost:5002"
WEBHOOK_ENDPOINT="/webhooks/tradingview"

echo "🎯 Focused Capital-Aware Sizing Test"
echo "===================================="
echo "Testing NIFTY and BANKNIFTY with different capital amounts"
echo ""

# Function to send webhook and show capital band info
send_test() {
    local balance="$1"
    local ticker="$2"
    local signal="$3"
    local price="$4"

    echo "💰 Testing: ₹$balance balance | $ticker $signal"

    # Determine capital band
    if [ $balance -le 75000 ]; then
        band="₹50K → 30% allocation, 5% risk per trade"
    elif [ $balance -le 150000 ]; then
        band="₹1L → 25% allocation, 3.5% risk per trade"
    elif [ $balance -le 300000 ]; then
        band="₹2L-3L → 20% allocation, 3% risk per trade"
    else
        band="₹3L+ → 20% allocation, 2.5% risk per trade"
    fi

    echo "📊 Expected Band: $band"

    # Set exchange based on ticker
    case $ticker in
        "SENSEX")
            exchange="BSE"
            ;;
        *)
            exchange="NSE"
            ;;
    esac

    # Set action and position based on signal
    case $signal in
        "long_entry")
            action="buy"
            position="flat"
            ;;
        "long_exit")
            action="sell"
            position="long"
            ;;
        "short_entry")
            action="sell"
            position="flat"
            ;;
        "short_exit")
            action="buy"
            position="short"
            ;;
    esac

    payload='{
      "alert": {
        "ticker": "'$ticker'",
        "instrument_type": "index",
        "action": "'$action'",
        "order_type": "market",
        "current_position": "'$position'",
        "strategy_type": "intraday",
        "current_price": '$price',
        "time": "'$(date -u +%Y-%m-%dT%H:%M:%S.000Z)'",
        "chart_interval": "1",
        "signal_type": "'$signal'",
        "strategy_name": "Enhanced AlgoTrading Alerts",
        "strategy_id": "'$ticker'_intraday",
        "exchange": "'$exchange'"
      }
    }'

    response=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
        -X POST \
        -H "Content-Type: application/json" \
        -H "X-Available-Balance: $balance" \
        -d "$payload" \
        "$BASE_URL$WEBHOOK_ENDPOINT")

    http_code=$(echo "$response" | grep "HTTP_CODE:" | cut -d: -f2)
    body=$(echo "$response" | sed '/HTTP_CODE:/d')

    echo "📥 Result (HTTP $http_code):"
    echo "$body" | jq -r '.message // .error' 2>/dev/null || echo "$body"

    # Check if processed successfully
    if echo "$body" | grep -q '"status":"processed"'; then
        echo "✅ SUCCESS: Alert processed with capital-aware sizing"
    elif echo "$body" | grep -q '"status":"failed"'; then
        echo "❌ FAILED: $(echo "$body" | jq -r '.error_message // "Unknown error"' 2>/dev/null)"
    else
        echo "⚠️  UNKNOWN: Unexpected response"
    fi

    echo "----------------------------------------"
    echo ""
}

# Test NIFTY with different capital amounts
echo "🚀 Testing NIFTY Long Entry with Capital-Aware Sizing"
echo ""

send_test "50000" "NIFTY" "long_entry" "22900.9"
send_test "100000" "NIFTY" "long_entry" "22900.9"
send_test "150000" "NIFTY" "long_entry" "22900.9"
send_test "200000" "NIFTY" "long_entry" "22900.9"
send_test "300000" "NIFTY" "long_entry" "22900.9"
send_test "500000" "NIFTY" "long_entry" "22900.9"

echo "🚀 Testing BANKNIFTY Long Entry with Capital-Aware Sizing"
echo ""

send_test "100000" "BANKNIFTY" "long_entry" "48500.2"
send_test "200000" "BANKNIFTY" "long_entry" "48500.2"
send_test "300000" "BANKNIFTY" "long_entry" "48500.2"

echo "🚀 Testing BANKNIFTY Short Entry with Capital-Aware Sizing"
echo ""

send_test "150000" "BANKNIFTY" "short_entry" "48200.8"
send_test "250000" "BANKNIFTY" "short_entry" "48200.8"

echo "✅ Capital-Aware Sizing Test Complete!"
echo ""
echo "📈 Summary of Capital Bands:"
echo "   ₹50K  → 30% allocation, 5% risk per trade"
echo "   ₹1L   → 25% allocation, 3.5% risk per trade"
echo "   ₹1.5L → 25% allocation, 3.5% risk per trade"
echo "   ₹2L   → 20% allocation, 3% risk per trade"
echo "   ₹3L   → 20% allocation, 3% risk per trade"
echo "   ₹5L   → 20% allocation, 2.5% risk per trade"
