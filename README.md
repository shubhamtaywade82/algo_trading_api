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


## 🔒 Order Placement Safety

All broker order placement is centralized in `Orders::Gateway`.

- Live order execution requires **both** `PLACE_ORDER=true` (this app's gate) and
  `LIVE_TRADING=true` (the DhanHQ SDK's own gate, added in gem 2.7).
- When either is disabled, the gateway blocks placement, logs the attempt, and returns a deterministic dry-run style response naming the switch that blocked it.
- New order flows must call the gateway instead of invoking `DhanHQ::Models::Order` / `SuperOrder` directly.

> Setting only `PLACE_ORDER=true` will not place orders — the SDK raises
> `DhanHQ::LiveTradingDisabledError` on every mutation until `LIVE_TRADING=true`
> is also set.

### Tradable books

`Orders::Gateway` routes an order to the right DhanHQ surface for its asset class:

| asset class | method | DhanHQ surface | currency |
|---|---|---|---|
| equity, index, options, futures, currency, commodity | `place_order` / `place_super_order` | `Models::Order` / `SuperOrder` | INR |
| US equities | `place_global_order` | `Models::GlobalStocks::Order` | USD |
| multi-leg basket (≤ 15 legs) | `place_basket_order` | `Models::MultiOrder` | INR |

`Gateway.place(payload)` infers the book: an `INX_EQ` segment, or a non-numeric
`security_id` (a ticker like `AAPL`) with no segment, routes to Global Stocks.
US orders carry no exchange segment, product type or validity, take float
quantities for fractional shares, and support the notional `AMOUNT` order type.

## 📡 Live market feed

`Live::MarketFeedHub` owns one WebSocket per process, wrapping
`DhanHQ::WS::Client`. Decoded ticks land in `Live::TickCache` (in-process,
30s TTL) and readers consult it before falling back to REST — so
`Instrument#ltp` is free while the feed is up.

```bash
bin/rails live:feed MODE=quote SYMBOLS=NSE_FNO:49081,IDX_I:13
bin/rails live:feed SUBSCRIBE_WATCHLIST=true   # subscribe every active watchlist item
bin/rails live:feed_health                     # one-shot health snapshot
```

Nothing starts the feed automatically. A process that never starts it degrades
to REST, which is why every reader checks `running? && connected?` first.

Two behaviours worth knowing:

- **Health is judged on frame arrival, not socket state.** A feed can stay
  connected while the server stops publishing, so `connected?` also requires a
  frame within 45s.
- **A reconnect clears the tick cache.** Prices from before the gap must not be
  traded on, so the cache is dropped and subscriptions replayed.

Dhan caps a connection at 5,000 instruments; the hub refuses subscriptions past
that rather than silently dropping them.

## 🧪 Paper trading

`PAPER_TRADING=true` routes `Orders::Gateway` to `Paper::Broker`. Because the
switch is at the gateway, every caller — alert processors, MCP tools,
`Orders::Executor` — gets paper behaviour with no code change, and the result
shape is identical to a live placement.

```bash
PAPER_TRADING=true bin/rails s
bin/rails live:paper_book    # positions, working orders, P&L and charges
bin/rails live:paper_eod     # square off intraday positions now
bin/rails live:paper_roll    # roll the book onto the current session
bin/rails live:paper_reset   # reset the book to its starting capital
```

This is a step beyond the SDK's `DHAN_DRY_RUN`, which suppresses the request and
returns a `DRYRUN-…` id without modelling the outcome. `Paper::Exchange` is a
simulated exchange over **real market data**:

- **Fills** against the live LTP (WebSocket cache first, REST fallback), with
  slippage applied **against the taker** — buys fill higher, sells lower.
- **Resting orders.** A non-marketable limit and an un-elected stop rest, then
  fill when a later tick reaches them. This is driven by the market feed, so
  `bin/rails live:feed` must be running for resting orders to work. The feed
  subscribes each instrument as the book trades it and re-subscribes anything
  still working on start-up, so an option strike chosen at signal time is
  ticked without being listed in `SYMBOLS`.
- **Its own capital and its own positions.** Sizing and every guard — entry
  dedupe, flips, exits, the daily-loss cap — read the paper book while
  `PAPER_TRADING=true`, not the live account.
- **Super orders.** Once the entry fills, a tick through the target or stop
  closes the position, whichever comes first. A `trailing_jump` ratchets the
  stop in whole jumps as price advances, and never gives it back.
- **Session boundaries.** INTRADAY positions are squared off at 15:15 IST as the
  broker would; MARGIN and CNC carry forward. On the next session the book is
  rolled: DAY orders expire, flat positions are dropped and last session's
  realised P&L is cleared, so the daily-loss guard counts today only.
- **Virtual capital and margin.** Orders are rejected when the book cannot fund
  them; margin is blocked on placement and released on fill or cancel.
- **Real Dhan charges** per fill, including the STT asymmetry (sell-side for
  intraday and F&O, both sides for delivery) that makes an intraday P&L look
  better than it is when ignored.
- **Partial fills**, optional, with a configurable fill probability.

Configure per account through `PaperAccount.current.config`:

| key | values | default |
|---|---|---|
| `slippage_model` | `fixed_bps`, `spread_based`, `volume_based`, `none` | `fixed_bps` |
| `slippage_bps` | 0–100 | 5 |
| `fill_probability` | 0.0–1.0 | 1.0 |
| `partial_fill_enabled` | true/false | false |
| `market_hours_enforced` | true/false | true |

`spread_based` uses half the live bid/ask from the feed's depth — the most
honest model when depth is available. `volume_based` applies square-root market
impact for sizing studies.

**What it does not model:** queue position, and margin is a flat per-segment
approximation rather than SPAN. It is conservative for option buying and
**understates naked option selling**, where real SPAN is far higher — don't use
paper margin to size a short-vol strategy.

### Alert routing by asset class

`AlertProcessorFactory` maps an alert's `instrument_type` to a processor:

| `instrument_type` | processor | book |
|---|---|---|
| `stock` | `AlertProcessors::Stock` | NSE/BSE equity |
| `index` | `AlertProcessors::Index` | index options |
| `futures` | `AlertProcessors::McxCommodity` | MCX commodity |
| `global_equity` | `AlertProcessors::GlobalEquity` | US equity (USD) |

`GlobalEquity` is deliberately unlike the others: US tickers are not in the
`instruments` scrip master (the alert's ticker *is* the `security_id`), sizing
reads the USD `GlobalStocks::Funds` balance rather than the domestic fund limit,
quantities are fractional, and the open check uses `GlobalStocks::MarketStatus`
because `MarketCalendar` only knows NSE/BSE hours. The SDK does not run its risk
pipeline on this book, so the processor's own guards are the only pre-trade
limits — it fails closed when market status is unavailable.

### Failed writes are never retried

DhanHQ ≥ 3.2 stopped auto-retrying order placement/modify/cancel — the API has
no idempotency key, so a timed-out `POST /v2/orders` may already have reached
the exchange. The gateway returns `reconcilable: true` with the
`correlation_id` instead; reconcile via `GET /v2/orders/external/{id}` before
resubmitting. `DHAN_AUTO_CORRELATION_ID` (default on) stamps an id so that
lookup always works. Set `DHAN_RETRY_WRITES=true` only if you accept duplicates.

### Rehearsal mode

`DHAN_DRY_RUN=true` puts the **SDK** in dry-run: every state-changing request is
suppressed and placements return a simulated `DRYRUN-…` id, while reads still
hit the live API — so a full strategy can be rehearsed against real prices.
This is distinct from `PLACE_ORDER=false`, which short-circuits in this app
before the SDK is called at all.

## 🤖 MCP (Model Context Protocol)

The app exposes a **read-only DhanHQ MCP server** over HTTP so AI assistants (e.g. Cursor) and other MCP clients can call broker and market tools via JSON-RPC.

- **Endpoint**: `POST /mcp`
- **Local**: `http://localhost:5002/mcp` (or your `PORT`). For deployed app, use your app’s base URL + `/mcp`.
- **Auth**: `MCP_ACCESS_TOKEN` is required; set it in `.env` and send as `Authorization: Bearer <token>` on every request. If unset, the server returns 503.

Available tools include: `get_holdings`, `get_positions`, `get_fund_limits`, `get_order_list`, `get_order_by_id`, `get_trade_book`, `get_trade_history`, `get_instrument`, `get_market_ohlc`, `get_historical_daily_data`, `get_intraday_minute_data`, `get_option_chain`, `get_expiry_list`, `get_edis_inquiry`.

Full docs, argument shapes, and example `curl` calls: **[docs/MCP.md](docs/MCP.md)**.

The HTTP MCP transport may wrap tool inputs inside a `params` envelope and attach `server_context`; both the production MCP dispatcher and the Dhan MCP tool definitions normalize that payload before validation so live tool calls do not fail on keyword mismatches.
Some imported OpenAPI action clients also send the tool payload under a top-level `arguments` key instead of `params`; the server now accepts that compatibility shape too, but `params` remains the canonical format documented in `docs/mcp_openapi.yaml`.

## 🤖 AI Agents (orchestration layer)

The app exposes an **AI agents orchestration layer** for trading intelligence: market analysis, options flow, trade proposals, position review, and operational Q&A. It uses the [chatwoot/ai-agents](https://github.com/chatwoot/ai-agents) gem.

- **Endpoints:** `POST /ai_agents/analyze`, `POST /ai_agents/propose`, `POST /ai_agents/ask`, `GET /ai_agents/positions`, `GET /ai_agents/session_report`
- **Auth:** Set `AI_AGENTS_ACCESS_TOKEN` and send `Authorization: Bearer <token>` (optional; if unset, no auth).
- **Scope:** Analysis and proposals only — the AI layer never places orders; execution goes through `Strategy::Validator` and the existing order pipeline.

Full docs, configuration, request/response shapes, and Ruby usage: **[docs/AI_AGENTS.md](docs/AI_AGENTS.md)**.

## 🏗️ Architecture

### Core Components

#### Alert Processors
- **`AlertProcessors::Index`** - Handles NIFTY, BANKNIFTY, SENSEX options trading (uses `AlertProcessors::IndexPositionManager` for position handling)
- **`AlertProcessors::Stock`** - Handles direct equity trading
- **`AlertProcessors::McxCommodity`** - Handles commodity futures trading

### Key Services
- **`Dhan::MarketDataService`** - Centralized DhanHQ API interaction for all instruments
- **`Market::SentimentService`** - Orchestrates sentiment analysis and strategy suggestions
- **`Market::AnalysisUpdater`** - Periodic technical analysis updates for key indices
- **`Alerts::InstrumentResolver`** - Robust instrument resolution from webhook parameters
- **`InstrumentsImport::*`** - Modular scrip master import pipeline (Fetcher, Parser, Mapper, Upserter)
- **Capital-Aware Sizing** - Dynamic position sizing based on account balance
- **Risk Management** - Stop-loss and daily loss protection
- **Market Data Processing** - Real-time price and volume analysis (via `CandleSeries` and modular indicators)
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

# Broker API (Dhan) — OAuth; one-time login at /auth/dhan/login (see docs/DHAN_AUTH.md)
DHAN_CLIENT_ID=your_client_id
DHAN_CLIENT_SECRET=your_client_secret

# AI Agents (see docs/AI_AGENTS.md)
OPENAI_API_KEY=sk-...
# AI_AGENTS_ACCESS_TOKEN=optional_bearer_token_for_ai_agents_endpoints
# OPENAI_URI_BASE=http://localhost:11434/v1   # Ollama
# OPENAI_OLLAMA_MODEL=qwen3:latest

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
