# algo_trading_api

Rails 8 API backend for **signal-driven** algorithmic trading on Indian markets (NSE/BSE). Receives TradingView webhooks, processes signals, executes orders via DhanHQ v2.

## Stack

- Ruby on Rails 8, API-only mode
- PostgreSQL
- Redis (caching, market data)
- Sidekiq or similar for background jobs
- DhanHQ v2 via `dhanhq-client` gem

## Commands

```bash
bundle install
rails db:setup                     # create + migrate + seed
rails db:migrate
bundle exec rspec                  # all specs
bundle exec rspec spec/path/file_spec.rb
bundle exec rubocop
rails server                       # dev server
```

## Architecture

```
app/
  controllers/
    webhooks/          # TradingView + DhanHQ postback ingestion
    options/           # Strategy suggestions
    admin/             # Settings
    funds/, portfolios/, statements/
  services/
    dhan/              # Auth, token manager, WS feed, postback handler
    orders/            # adjuster, analyzer, bracket_placer, executor, manager, risk_manager
    indicators/        # Technical indicators
    option/            # Options chain + strategy logic
    market/            # Market feed helpers, calendar, cache
    openai/            # Optional AI analysis
```

## Entry points

- **Webhooks**: `POST /webhooks/tradingview` → `Webhooks::AlertsController#create`
- **DhanHQ postbacks**: `POST /webhooks/dhan_postback` → `Webhooks::DhanPostbacksController#create`

## Capital bands (from README)

| Balance | Allocation | Risk/trade | Daily max loss |
|---|---|---|---|
| ≤ ₹75K | 30% | 5.0% | 5.0% |
| ≤ ₹1.5L | 25% | 3.5% | 6.0% |
| ≤ ₹3L | 20% | 3.0% | 6.0% |
| > ₹3L | 20% | 2.5% | 5.0% |

Override via env: `ALLOC_PCT`, `RISK_PER_TRADE_PCT`, `DAILY_MAX_LOSS_PCT`.

## Architecture decisions

These were evaluated against the TradingOS reference design and settled in favour
of what this repo already does. Don't re-open them without a concrete reason.

- **Single account, not multi-user.** There is no `User` model, `DhanAccessToken`
  is a single row, and the SDK's configuration is a process-global singleton that
  cannot hold two accounts' credentials at once. A per-user `ClientFactory` would
  require process-per-account. Keep the global config.
- **`Strategy` is the option-strategy playbook catalogue** (`name`, `objective`,
  `risk`, `reward`, ...) consumed by `Option::StrategySuggester`. It is *not* a
  deployment lifecycle. Service classes nest under it by reopening the class
  (`class Strategy; class Validator`) — never `module Strategy`, which raises
  `TypeError: Strategy is not a module`. A deployed-automation concept, if ever
  needed, takes a different name.
- **Signal-driven, not a polling engine.** Execution flows
  webhook → `Alert` → `AlertProcessorFactory` → `AlertProcessors::*` → `Orders::Gateway`.
  New asset classes are added as processors, not as a parallel strategy loop.

## Live feed and paper trading

- **`Live::MarketFeedHub`** owns one WebSocket per process (wraps
  `DhanHQ::WS::Client`); ticks land in `Live::TickCache`. Readers must check
  `running? && connected?` and fall back to REST — nothing starts the feed
  automatically. `connected?` requires a recent *frame*, not just a live socket.
- **A reconnect clears `TickCache`.** Never mark or trade against a price from
  before the gap.
- **`PAPER_TRADING=true`** routes `Orders::Gateway` to `Paper::Broker`. Paper
  mode bypasses `PLACE_ORDER`/`LIVE_TRADING` on purpose: nothing reaches the
  broker, so those gates have nothing to protect. Paper fills are `Order` rows
  with a `PAPER-` id; `Paper::Positions` derives the book from them.
- Distinct from `DHAN_DRY_RUN`, which is the SDK suppressing requests. Paper
  mode simulates fills, positions and P&L with real charges.

## Critical rules

- **DhanHQ only** — no Delta Exchange references anywhere in this repo
- Webhook processing must be **idempotent** — TradingView can resend
- Business logic lives in `app/services/`, not controllers
- Risk calculations must be **pure functions** (no DB side effects inside calculation logic)
- All order state transitions must be logged
- **Order placement invariant**: every live order placement must go through `Orders::Gateway` (guards both `PLACE_ORDER` and the SDK's `LIVE_TRADING`). No direct `DhanHQ::Models::Order.new/save`, `Order.place`, `SuperOrder.create`, `GlobalStocks::Order.place`, or `MultiOrder.create` outside the gateway.
- **Never retry a failed order write.** DhanHQ ≥ 3.2 stopped auto-retrying writes because the API has no idempotency key — a timed-out placement may already be live. The gateway returns `reconcilable: true`; reconcile by `correlation_id` instead.
- **SDK skills that mutate** (`square_off_all`, `square_off_position`, tagged `risk "destructive_write"`) bypass the gateway by design, so they must be invoked through `Dhan::SkillsService`, which applies the same gates.
- Use `after_commit`, never `after_save`, for side effects (emails, queues)
- `Time.current` everywhere, never `Time.now`
- `rescue StandardError`, never `rescue Exception`

## Ruby Mastery

Use `ruby_mastery` to understand and monitor the codebase:
- `ruby_mastery architecture score .`: Project health and domain structure.
- `ruby_mastery architect .`: Structural summary for refactor planning.
- `ruby_mastery architecture graph .`: Dependency visualization.
- `ruby_mastery analyze .`: Static analysis for idioms and violations.
