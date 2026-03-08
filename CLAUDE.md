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

## Critical rules

- **DhanHQ only** — no Delta Exchange references anywhere in this repo
- Webhook processing must be **idempotent** — TradingView can resend
- Business logic lives in `app/services/`, not controllers
- Risk calculations must be **pure functions** (no DB side effects inside calculation logic)
- All order state transitions must be logged
- Use `after_commit`, never `after_save`, for side effects (emails, queues)
- `Time.current` everywhere, never `Time.now`
- `rescue StandardError`, never `rescue Exception`

## Ruby Mastery

Use `ruby_mastery` to understand and monitor the codebase:
- `ruby_mastery architecture score .`: Project health and domain structure.
- `ruby_mastery architect .`: Structural summary for refactor planning.
- `ruby_mastery architecture graph .`: Dependency visualization.
- `ruby_mastery analyze .`: Static analysis for idioms and violations.
