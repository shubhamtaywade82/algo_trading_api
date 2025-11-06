# Algo Trading API

A sophisticated algorithmic trading system built with Ruby on Rails that provides capital-aware position sizing, real-time market data processing, and automated trading execution for Indian markets.

## 🚀 Features

### Capital-Aware Position Sizing
- **Dynamic Capital Bands**: Automatically adjusts position sizing based on account balance
- **Risk Management**: Configurable risk per trade and daily maximum loss limits
- **ATR-Adaptive Stop Loss**: Uses Average True Range for dynamic stop-loss calculation
- **Allocation Constraints**: Ensures optimal capital deployment per trade
- **Graceful Fallback**: Allows 1-lot trades when allocation is tight but risk/cash permits

### Trading Capabilities
- **Multi-Exchange Support**: NSE (NIFTY, BANKNIFTY) and BSE (SENSEX)
- **Options Trading**: Automated call/put option selection and execution
- **Stock Trading**: Direct equity trading with capital-aware sizing
- **MCX Commodity Trading**: Commodity futures trading support
- **Real-time Processing**: WebSocket-based market data feeds

### Webhook Integration
- **TradingView Integration**: Seamless webhook processing for trading signals
- **Multiple Signal Types**: Support for long/short entry and exit signals
- **Capital-Aware Processing**: Automatic position sizing based on available balance
- **Comprehensive Testing**: Built-in webhook testing tools

## 📊 Capital Bands Configuration

The system uses predefined capital bands to determine position sizing:

| Balance Range | Allocation % | Risk per Trade % | Daily Max Loss % |
| ------------- | ------------ | ---------------- | ---------------- |
| ≤ ₹75K        | 30%          | 5.0%             | 5.0%             |
| ≤ ₹1.5L       | 25%          | 3.5%             | 6.0%             |
| ≤ ₹3L         | 20%          | 3.0%             | 6.0%             |
| > ₹3L         | 20%          | 2.5%             | 5.0%             |

### Environment Variable Overrides
```bash
# Override default allocation percentage
export ALLOC_PCT=0.25

# Override default risk per trade percentage
export RISK_PER_TRADE_PCT=0.03

# Override default daily maximum loss percentage
export DAILY_MAX_LOSS_PCT=0.05
```

## 🛠️ Installation

### Prerequisites
- Ruby 3.3.4
- Rails 7.x
- PostgreSQL
- Redis (for caching)

### Setup
```bash
# Clone the repository
git clone <repository-url>
cd algo_trading_api

# Install dependencies
bundle install

# Setup database
rails db:create
rails db:migrate
rails db:seed

# Start the server
rails server
```

## 🧪 Testing

### Running Tests
```bash
# Run all tests
bundle exec rspec

# Run specific test files
bundle exec rspec spec/services/alert_processors/capital_aware_sizing_spec.rb
bundle exec rspec spec/services/alert_processors/index_spec.rb
```

### Webhook Testing

The system includes comprehensive webhook testing tools:

#### Quick Single Tests
```bash
# Test NIFTY with ₹1L balance
./test_single_webhook.sh 100000 NIFTY long_entry

# Test BANKNIFTY with ₹2L balance
./test_single_webhook.sh 200000 BANKNIFTY long_entry

# Test SENSEX with ₹3L balance (BSE exchange)
./test_single_webhook.sh 300000 SENSEX long_entry
```

#### Comprehensive Test Suite
```bash
# Run all webhook tests with different capital amounts
./test_webhook.sh

# Run focused capital-aware sizing tests
./test_focused_webhook.sh
```

### Exchange Mapping
- **NIFTY** → NSE (National Stock Exchange)
- **BANKNIFTY** → NSE (National Stock Exchange)
- **SENSEX** → BSE (Bombay Stock Exchange)

## 📡 Webhook Integration

### TradingView Webhook Setup

1. **Configure TradingView Alert**:
   ```json
   {
     "alert": {
       "ticker": "NIFTY",
       "instrument_type": "index",
       "action": "buy",
       "order_type": "market",
       "current_position": "flat",
       "strategy_type": "intraday",
       "current_price": 22900.9,
       "time": "{{$isoTimestamp}}",
       "chart_interval": "1",
       "signal_type": "long_entry",
       "strategy_name": "Enhanced AlgoTrading Alerts",
       "strategy_id": "NIFTY_intraday",
       "exchange": "NSE"
     }
   }
   ```

2. **Set Webhook URL**: `http://your-server:5002/webhooks/tradingview`

3. **Include Available Balance**: Add `X-Available-Balance` header with your account balance

### Supported Signal Types
- `long_entry` - Enter long position
- `long_exit` - Exit long position
- `short_entry` - Enter short position
- `short_exit` - Exit short position

## 🏗️ Architecture

### Core Components

#### Alert Processors
- **`AlertProcessors::Index`** - Handles NIFTY, BANKNIFTY, SENSEX options trading
- **`AlertProcessors::Stock`** - Handles direct equity trading
- **`AlertProcessors::McxCommodity`** - Handles commodity futures trading

#### Key Services
- **Capital-Aware Sizing** - Dynamic position sizing based on account balance
- **Risk Management** - Stop-loss and daily loss protection
- **Market Data Processing** - Real-time price and volume analysis
- **Order Execution** - Automated trade execution via broker APIs

### Database Schema
- **Instruments** - Market instruments and their metadata
- **Alerts** - Trading signals and their processing status
- **Positions** - Current trading positions
- **Orders** - Order execution history

## 🔧 Configuration

### Environment Variables
```bash
# Database
DATABASE_URL=postgresql://user:password@localhost/algo_trading_api

# Redis
REDIS_URL=redis://localhost:6379/0

# Broker API (Dhan)
DHAN_API_KEY=your_api_key
ACCESS_TOKEN=your_access_token

# Capital Management
ALLOC_PCT=0.25
RISK_PER_TRADE_PCT=0.03
DAILY_MAX_LOSS_PCT=0.05
```

### Dhan Postback URL

When generating the Dhan access token, point the **Postback URL** to the Rails webhook endpoint so order updates land in the app:

```
https://<your-public-host>/webhooks/dhan_postback
```

Use a publicly reachable HTTPS URL (for example, via ngrok while developing) because Dhan ignores `localhost` or `127.0.0.1` callbacks.

### Capital Bands Customization
Edit the `CAPITAL_BANDS` constant in alert processors to customize:
```ruby
CAPITAL_BANDS = [
  { upto: 75_000, alloc_pct: 0.30, risk_per_trade_pct: 0.050, daily_max_loss_pct: 0.050 },
  { upto: 150_000, alloc_pct: 0.25, risk_per_trade_pct: 0.035, daily_max_loss_pct: 0.060 },
  { upto: 300_000, alloc_pct: 0.20, risk_per_trade_pct: 0.030, daily_max_loss_pct: 0.060 },
  { upto: Float::INFINITY, alloc_pct: 0.20, risk_per_trade_pct: 0.025, daily_max_loss_pct: 0.050 }
].freeze
```

## 📈 Usage Examples

### Basic Trading Signal
```bash
curl -X POST http://localhost:5002/webhooks/tradingview \
  -H "Content-Type: application/json" \
  -H "X-Available-Balance: 100000" \
  -d '{
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
      "strategy_name": "My Strategy",
      "strategy_id": "NIFTY_intraday",
      "exchange": "NSE"
    }
  }'
```

### Expected Response
```json
{
  "message": "Alert processed successfully",
  "alert": {
    "id": 123,
    "ticker": "NIFTY",
    "status": "processed",
    "action": "buy",
    "exchange": "NSE",
    "instrument_id": 351776,
    "created_at": "2024-01-15T10:30:00.000Z"
  }
}
```

## 🚨 Risk Management

### Built-in Protections
- **Daily Loss Guard** - Prevents new trades when daily loss exceeds limits
- **Position Size Limits** - Caps position size based on available capital
- **Stop Loss Protection** - ATR-adaptive stop losses for risk management
- **Allocation Constraints** - Ensures optimal capital deployment

### Monitoring
- Real-time position tracking
- P&L monitoring and alerts
- Risk metrics dashboard
- Trade execution logs

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🆘 Support

For issues and questions:
1. Check the troubleshooting section in `manual_test_commands.md`
2. Review the test files for usage examples
3. Open an issue on GitHub

## 🔄 Changelog

### v1.0.0
- Initial release with capital-aware position sizing
- TradingView webhook integration
- Multi-exchange support (NSE, BSE)
- Comprehensive testing suite
- Risk management features