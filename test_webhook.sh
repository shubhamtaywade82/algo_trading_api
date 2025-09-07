#!/bin/bash

# Test TradingView Webhook Listener with Capital-Aware Sizing
# Server running on http://localhost:5002

BASE_URL="http://localhost:5002"
WEBHOOK_ENDPOINT="/webhooks/tradingview"

echo "🚀 Testing TradingView Webhook Listener with Capital-Aware Sizing"
echo "================================================================"

# Function to send webhook with custom balance
send_webhook() {
    local test_name="$1"
    local balance="$2"
    local payload="$3"

    echo ""
    echo "📊 Test: $test_name"
    echo "💰 Available Balance: ₹$balance"
    echo "📤 Payload: $payload"

    # Set the available balance via environment variable or header
    response=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
        -X POST \
        -H "Content-Type: application/json" \
        -H "X-Available-Balance: $balance" \
        -d "$payload" \
        "$BASE_URL$WEBHOOK_ENDPOINT")

    http_code=$(echo "$response" | grep "HTTP_CODE:" | cut -d: -f2)
    body=$(echo "$response" | sed '/HTTP_CODE:/d')

    echo "📥 Response (HTTP $http_code):"
    echo "$body" | jq . 2>/dev/null || echo "$body"
    echo "----------------------------------------"
}

# Test NIFTY Long Entry with ₹50K balance
send_webhook "NIFTY Long Entry - ₹50K Balance" "50000" '{
  "alert": {
    "ticker": "NIFTY",
    "instrument_type": "index",
    "action": "buy",
    "order_type": "market",
    "current_position": "flat",
    "strategy_type": "intraday",
    "current_price": 22900.9,
    "time": "2024-01-15T10:30:00.000Z",
    "chart_interval": "1",
    "signal_type": "long_entry",
    "strategy_name": "Enhanced AlgoTrading Alerts",
    "strategy_id": "NIFTY_intraday",
    "exchange": "NSE"
  }
}'

# Test NIFTY Long Entry with ₹1L balance
send_webhook "NIFTY Long Entry - ₹1L Balance" "100000" '{
  "alert": {
    "ticker": "NIFTY",
    "instrument_type": "index",
    "action": "buy",
    "order_type": "market",
    "current_position": "flat",
    "strategy_type": "intraday",
    "current_price": 22900.9,
    "time": "2024-01-15T10:30:00.000Z",
    "chart_interval": "1",
    "signal_type": "long_entry",
    "strategy_name": "Enhanced AlgoTrading Alerts",
    "strategy_id": "NIFTY_intraday",
    "exchange": "NSE"
  }
}'

# Test NIFTY Long Entry with ₹1.5L balance
send_webhook "NIFTY Long Entry - ₹1.5L Balance" "150000" '{
  "alert": {
    "ticker": "NIFTY",
    "instrument_type": "index",
    "action": "buy",
    "order_type": "market",
    "current_position": "flat",
    "strategy_type": "intraday",
    "current_price": 22900.9,
    "time": "2024-01-15T10:30:00.000Z",
    "chart_interval": "1",
    "signal_type": "long_entry",
    "strategy_name": "Enhanced AlgoTrading Alerts",
    "strategy_id": "NIFTY_intraday",
    "exchange": "NSE"
  }
}'

# Test NIFTY Long Entry with ₹2L balance
send_webhook "NIFTY Long Entry - ₹2L Balance" "200000" '{
  "alert": {
    "ticker": "NIFTY",
    "instrument_type": "index",
    "action": "buy",
    "order_type": "market",
    "current_position": "flat",
    "strategy_type": "intraday",
    "current_price": 22900.9,
    "time": "2024-01-15T10:30:00.000Z",
    "chart_interval": "1",
    "signal_type": "long_entry",
    "strategy_name": "Enhanced AlgoTrading Alerts",
    "strategy_id": "NIFTY_intraday",
    "exchange": "NSE"
  }
}'

# Test NIFTY Long Entry with ₹3L balance
send_webhook "NIFTY Long Entry - ₹3L Balance" "300000" '{
  "alert": {
    "ticker": "NIFTY",
    "instrument_type": "index",
    "action": "buy",
    "order_type": "market",
    "current_position": "flat",
    "strategy_type": "intraday",
    "current_price": 22900.9,
    "time": "2024-01-15T10:30:00.000Z",
    "chart_interval": "1",
    "signal_type": "long_entry",
    "strategy_name": "Enhanced AlgoTrading Alerts",
    "strategy_id": "NIFTY_intraday",
    "exchange": "NSE"
  }
}'

# Test NIFTY Long Entry with ₹5L balance
send_webhook "NIFTY Long Entry - ₹5L Balance" "500000" '{
  "alert": {
    "ticker": "NIFTY",
    "instrument_type": "index",
    "action": "buy",
    "order_type": "market",
    "current_position": "flat",
    "strategy_type": "intraday",
    "current_price": 22900.9,
    "time": "2024-01-15T10:30:00.000Z",
    "chart_interval": "1",
    "signal_type": "long_entry",
    "strategy_name": "Enhanced AlgoTrading Alerts",
    "strategy_id": "NIFTY_intraday",
    "exchange": "NSE"
  }
}'

# Test NIFTY Long Exit
send_webhook "NIFTY Long Exit" "100000" '{
  "alert": {
    "ticker": "NIFTY",
    "instrument_type": "index",
    "action": "sell",
    "order_type": "market",
    "current_position": "long",
    "strategy_type": "intraday",
    "current_price": 23150.5,
    "time": "2024-01-15T11:45:00.000Z",
    "chart_interval": "1",
    "signal_type": "long_exit",
    "strategy_name": "Enhanced AlgoTrading Alerts",
    "strategy_id": "NIFTY_intraday",
    "exchange": "NSE"
  }
}'

# Test BANKNIFTY Long Entry with ₹1.5L balance
send_webhook "BANKNIFTY Long Entry - ₹1.5L Balance" "150000" '{
  "alert": {
    "ticker": "BANKNIFTY",
    "instrument_type": "index",
    "action": "buy",
    "order_type": "market",
    "current_position": "flat",
    "strategy_type": "intraday",
    "current_price": 48500.2,
    "time": "2024-01-15T10:30:00.000Z",
    "chart_interval": "1",
    "signal_type": "long_entry",
    "strategy_name": "Enhanced AlgoTrading Alerts",
    "strategy_id": "BANKNIFTY_intraday",
    "exchange": "NSE"
  }
}'

# Test BANKNIFTY Short Entry with ₹2L balance
send_webhook "BANKNIFTY Short Entry - ₹2L Balance" "200000" '{
  "alert": {
    "ticker": "BANKNIFTY",
    "instrument_type": "index",
    "action": "sell",
    "order_type": "market",
    "current_position": "flat",
    "strategy_type": "intraday",
    "current_price": 48200.8,
    "time": "2024-01-15T11:00:00.000Z",
    "chart_interval": "1",
    "signal_type": "short_entry",
    "strategy_name": "Enhanced AlgoTrading Alerts",
    "strategy_id": "BANKNIFTY_intraday",
    "exchange": "NSE"
  }
}'

# Test SENSEX Long Entry with ₹3L balance
send_webhook "SENSEX Long Entry - ₹3L Balance" "300000" '{
  "alert": {
    "ticker": "SENSEX",
    "instrument_type": "index",
    "action": "buy",
    "order_type": "market",
    "current_position": "flat",
    "strategy_type": "intraday",
    "current_price": 72500.3,
    "time": "2024-01-15T10:30:00.000Z",
    "chart_interval": "1",
    "signal_type": "long_entry",
    "strategy_name": "Enhanced AlgoTrading Alerts",
    "strategy_id": "SENSEX_intraday",
    "exchange": "BSE"
  }
}'

# Test SENSEX Long Exit with ₹5L balance
send_webhook "SENSEX Long Exit - ₹5L Balance" "500000" '{
  "alert": {
    "ticker": "SENSEX",
    "instrument_type": "index",
    "action": "sell",
    "order_type": "market",
    "current_position": "long",
    "strategy_type": "intraday",
    "current_price": 72800.7,
    "time": "2024-01-15T12:00:00.000Z",
    "chart_interval": "1",
    "signal_type": "long_exit",
    "strategy_name": "Enhanced AlgoTrading Alerts",
    "strategy_id": "SENSEX_intraday",
    "exchange": "BSE"
  }
}'

echo ""
echo "✅ All webhook tests completed!"
echo "📊 Expected Capital-Aware Sizing Results:"
echo "   ₹50K  → 30% allocation, 5% risk per trade"
echo "   ₹1L   → 25% allocation, 3.5% risk per trade"
echo "   ₹1.5L → 25% allocation, 3.5% risk per trade"
echo "   ₹2L   → 20% allocation, 3% risk per trade"
echo "   ₹3L   → 20% allocation, 3% risk per trade"
echo "   ₹5L   → 20% allocation, 2.5% risk per trade"
