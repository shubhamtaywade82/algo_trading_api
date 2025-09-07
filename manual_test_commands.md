# Manual Webhook Testing Commands

## Quick Test Commands

### Test NIFTY with Different Capital Amounts

```bash
# ₹50K balance - Should use 30% allocation, 5% risk per trade
./test_single_webhook.sh 50000 NIFTY long_entry

# ₹1L balance - Should use 25% allocation, 3.5% risk per trade
./test_single_webhook.sh 100000 NIFTY long_entry

# ₹1.5L balance - Should use 25% allocation, 3.5% risk per trade
./test_single_webhook.sh 150000 NIFTY long_entry

# ₹2L balance - Should use 20% allocation, 3% risk per trade
./test_single_webhook.sh 200000 NIFTY long_entry

# ₹3L balance - Should use 20% allocation, 3% risk per trade
./test_single_webhook.sh 300000 NIFTY long_entry

# ₹5L balance - Should use 20% allocation, 2.5% risk per trade
./test_single_webhook.sh 500000 NIFTY long_entry
```

### Test BANKNIFTY with Different Capital Amounts

```bash
# ₹1L balance
./test_single_webhook.sh 100000 BANKNIFTY long_entry

# ₹2L balance
./test_single_webhook.sh 200000 BANKNIFTY long_entry

# ₹3L balance
./test_single_webhook.sh 300000 BANKNIFTY long_entry
```

### Test Different Signal Types

```bash
# Long Entry
./test_single_webhook.sh 100000 NIFTY long_entry

# Long Exit
./test_single_webhook.sh 100000 NIFTY long_exit

# Short Entry
./test_single_webhook.sh 100000 BANKNIFTY short_entry

# Short Exit
./test_single_webhook.sh 100000 BANKNIFTY short_exit
```

## Expected Capital-Aware Sizing Results

| Balance | Allocation % | Risk per Trade % | Max Daily Loss % |
| ------- | ------------ | ---------------- | ---------------- |
| ₹50K    | 30%          | 5.0%             | 5.0%             |
| ₹1L     | 25%          | 3.5%             | 6.0%             |
| ₹1.5L   | 25%          | 3.5%             | 6.0%             |
| ₹2L     | 20%          | 3.0%             | 6.0%             |
| ₹3L     | 20%          | 3.0%             | 6.0%             |
| ₹5L     | 20%          | 2.5%             | 5.0%             |

## What to Look For

1. **HTTP 201** response code (success)
2. **"Alert processed successfully"** message
3. **Capital-aware sizing logs** in the response showing:
   - Allocation cap
   - Risk cap
   - Per-lot cost and risk
   - Total cost and risk
   - Stop loss percentage

## Troubleshooting

- **404 errors**: Instrument not found (SENSEX uses BSE exchange, not NSE)
- **"undefined method '[]' for nil"**: Missing data in option chain analysis
- **Trend mismatch warnings**: Expected behavior when market trend doesn't match signal
- **Quantity validation errors**: Exit signals need existing positions

## Exchange Mapping

- **NIFTY** → NSE (National Stock Exchange)
- **BANKNIFTY** → NSE (National Stock Exchange)
- **SENSEX** → BSE (Bombay Stock Exchange)

## Server Status

Make sure your server is running on `http://localhost:5002` before testing.
