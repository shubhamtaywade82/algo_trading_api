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

## Instrument master

The scrip-master schema and import pipeline have been through one round of
consolidation already (migrations `20260727130100`–`20260727140000`). The
decisions below are settled; each has a failure mode behind it.

- **`security_id` is unique per exchange segment, never globally.** NSE_EQ 2885
  and IDX_I 2885 are different instruments. The key is
  `(security_id, symbol_name, exchange, segment)` — `index_instruments_unique`,
  and the conflict target every upsert uses. A unique index on `security_id`
  alone would reject legitimate rows.
- **`isin` is not unique either.** One ISIN spans a company's NSE and BSE
  listings plus every derivative written against it.
- **There is no `trading_symbol` column.** The feed's symbol lands in
  `symbol_name`, with `display_name` (title-cased) and `underlying_symbol`
  alongside. `trading_symbol` exists only on the broker-payload tables
  (`positions`, `holdings`, `exit_logs`, `paper_*`). Resolve symbols through
  `Instrument.lookup_by_symbol`.
- **Trading rules live in satellite tables, not JSONB.** `order_features` and
  `margin_requirements` are polymorphic 1:1 satellites of Instrument/Derivative.
  The 22 rule columns were moved off the two hottest tables deliberately; a
  `jsonb` column would put them back, untyped, and needs a GIN index to answer
  what `tradable`'s join already answers.
- **`active` + `last_seen_at`, not `is_active`.** The importer stamps
  `last_seen_at` on every row the feed still lists and
  `InstrumentsImport::Deactivator` retires the rest. Renaming the column breaks
  the sweep.
- **CHECK constraints are the real guard, and they are added NOT VALID.**
  The importer writes through activerecord-import, which skips validations, so
  the model validations are for hand-built records only. New constraints go in
  `validate: false` so a legacy row cannot fail a deploy, then
  `bin/rails instruments:validate_constraints` promotes them.
- **Constrain the domain the exchange actually ships.** MCX sends
  `OPTION_TYPE = "XX"` on futures; `InstrumentsImport::Parser` normalises it to
  NULL, because a CE/PE check that meets it aborts the entire nightly import.
  An import that dies on one odd row is worse than the row.
- **The index segment is seeded, everything else is imported.**
  `db/seeds/index_instruments.csv` is the feed's own 191 IDX_I rows, loaded by
  `db/seeds.rb` through `InstrumentsImporter.import_from_csv` — the partial-feed
  entry point, which upserts on the same natural key and retires nothing. The
  full import is a 37 MB download of 218k rows and is opt-in on deploy
  (`IMPORT_INSTRUMENTS_ON_DEPLOY`), so without the seed a fresh database answers
  `/nifty_analysis` with "Instrument not found: NIFTY". Equities and derivatives
  still need `rails instruments:import`.
- **Every hash in an activerecord-import batch needs the same keys.**
  `InstrumentsImport::Mapper` sets `instrument_id` only on contracts whose
  underlying it resolved, and `Upserter` imports both halves as one batch so an
  unparented contract is stored rather than dropped — so it fills the key in on
  every row first. A real scrip master has both halves non-empty, and the mixed
  batch aborts the whole import with `Hash key mismatch`.
- **Caching contract lookups is an in-process decision.** Measured on 62k
  contracts, the options-chain index executes in 0.05ms but a full
  `Derivative.find_by` round trip is p50 1.3ms / p95 2.8ms — the cost is the
  round trip, not the index. `Rails.cache` here is solid_cache (Postgres), so a
  cache layer on top of it buys nothing; only an in-process Hash (0.002ms) is
  faster. That is why `Dhan::WS::FeedListener.find_instrument_cached` and
  `Live::TickCache` are plain Ruby hashes. Contract resolution in the order path
  runs once per order against a ~100ms broker call and is deliberately *not*
  cached: a stale security_id trades the wrong contract.

## Live feed and paper trading

- **`Live::MarketFeedHub`** owns one WebSocket per process (wraps
  `DhanHQ::WS::Client`); ticks land in `Live::TickCache`. Readers must check
  `running? && connected?` and fall back to REST — nothing starts the feed
  automatically. `connected?` requires a recent *frame*, not just a live socket.
- **A reconnect clears `TickCache`.** Never mark or trade against a price from
  before the gap.
- **`PAPER_TRADING=true`** routes `Orders::Gateway` to `Paper::Exchange`. Paper
  mode bypasses `PLACE_ORDER`/`LIVE_TRADING` on purpose: nothing reaches the
  broker, so those gates have nothing to protect.
- **Never pre-check `Orders::Gateway.place_order_enabled?` before placing.** The
  gateway routes to the paper book *before* it consults those gates, so a caller
  that decides "blocked" on its own behalf silently makes paper mode
  unreachable. Call the gateway and branch on the result.
- Paper state lives in `paper_accounts` / `paper_orders` / `paper_positions`
  (single account, like `DhanAccessToken`), never in the live `orders` table —
  a simulated fill must never be readable as a real position.
- **The read side must follow the write side.** In paper mode
  `AlertProcessors::Base#available_balance` and `#dhan_positions` serve the
  paper book (`Paper::Positions.dhan_shaped`, in the broker's key shape). Sizing
  or guarding against the live book during a paper run stacks duplicate entries
  and leaves the daily-loss cap reading zero.
- **Resting orders and super-order legs are driven by the feed.** `live:feed`
  has to be running or a limit/stop will never fill and marks will go stale.
  `Paper::FeedSubscriber` subscribes each instrument as it is traded and
  restores the open book on feed start, so a strike picked at signal time is
  ticked without anyone listing it in `SYMBOLS`.
- **The tick stream is the book's only clock.** `Paper::DayRollover` (expire
  DAY orders, drop flat positions, clear last session's realised P&L) and
  `Paper::EodSquareOff` (close INTRADAY at 15:15 IST; MARGIN and CNC are
  carry-forward and stay open) both hang off it, lazily and idempotently,
  because this app has no scheduler. `live:paper_roll` / `live:paper_eod` force
  them. Day scoping of the position view is the rollover's job — never a
  timestamp filter, which would hide a legitimate carry-forward position.
- **Exit management reads `Positions::Source`**, which serves the paper book in
  paper mode, so the existing `Positions::Manager` → `Orders::RiskManager` →
  `Orders::Executor` stack manages simulated positions too. Paper positions
  carry `costPrice` and `drvExpiryDate` because that stack reads them.
- **CNC lives in two places.** A delivery position is in the position book only
  on its trade date and in holdings from T+1, so exit logic checks
  `dhan_positions` then falls back to `dhan_holdings`. eDIS never runs in paper
  mode — it authorises a real depository debit.
- Distinct from `DHAN_DRY_RUN`, which is the SDK suppressing requests. Paper
  mode simulates fills, margin, positions and P&L with real charges.
- **`PAPER_CAPITAL` only applies to a book that does not exist yet.**
  `PaperAccount.current` reads it on create; re-capitalising a running book on
  every boot would rewrite the denominator of every P&L figure it has already
  produced. `rails live:paper_capital CAPITAL=…` applies a change deliberately,
  and clears the book with it.

## Index watchlist scanner

- **`live:paper_engine` is the autonomous side**, and it holds the feed *and*
  the scan loop in one process because `Live::TickCache` is process-local: a
  scanner elsewhere would place orders no tick stream ever fills. It cannot
  live in Puma either — `WEB_CONCURRENCY=2` forks would each open a socket.
- **`Market::ConfluenceTrader` is a signal source, not an execution path.** It
  turns a `ConfluenceDetector` signal into an `Alert` and hands it to
  `AlertProcessorFactory`, exactly as the webhook does, so strike selection,
  sizing, risk and exits stay in `AlertProcessors::Index` → `Orders::Gateway`.
  Anything it needs to decide differently belongs in the processor, not in a
  parallel path.
- **The roster is `Market::IndexWatchlist`, not a `Watchlist` row.**
  `Watchlist`/`WatchlistItem` are the equity universe `Watchlists::RefreshService`
  rebuilds daily; three indices that change about never do not need a table and
  a "traded nothing because the row was missing" failure mode.
- **The engine aborts unless `PAPER_TRADING` is on.** It places orders on its
  own initiative, so it must never be one env var away from doing that live.
  See `docs/PAPER_TRADING_INDICES.md`.
- **`MarketCalendar.market_open?` is the only definition of the session** —
  weekday, not on the holiday list, 09:15–15:30 IST, converted to IST rather
  than assumed. `Orders::PlaceOrderGuard`, `Paper::Exchange`,
  `Mcp::Tools::SystemStatus` and the scanner all delegate to it; they used to
  each carry a copy, and `Paper::Exchange`'s had drifted to a weekday-only
  check that accepted orders on market holidays. Don't reintroduce a local
  copy. `force: true` waives it, which is what lets `Paper::EodSquareOff` close
  positions after the bell.

## LLM layer

- **`Openai::ChatRouter` is the switch.** Every chat caller goes through it, so
  the backend is env-selected (`LLM_BACKEND=ollama_cloud`), never per-caller.
- **`Llm::KeyRotator` owns Ollama Cloud auth.** Up to five keys from
  `OLLAMA_API_KEY_1..5`, quarantined 5 minutes on 401/403/402/429/5xx. Never
  rotate on `BadRequestError`/`ModelNotFoundError` — those fail identically on
  every key and would burn the pool over a caller-side bug.
- **Never set `ollama_api_key` globally.** Keys are bound per request via
  `RubyLLM.context`; the feed thread and web requests share this process, so a
  global `RubyLLM.configure` swaps the key underneath a concurrent caller.
- `OLLAMA_API_BASE` must end in `/v1` — RubyLLM posts to
  `{base}/chat/completions`.
- Cloud model ids are absent from RubyLLM's registry, so chats need
  `provider: :ollama, assume_model_exists: true`.
- **`Llm::Tools::*` wrap `AI::Tools::*`**, never reimplement them — one copy of
  the DhanHQ plumbing. `use_new_acts_as` is set in `config/application.rb`
  because the railtie reads it before app initializers run.
- `ai-agents` must stay on a line allowing `ruby_llm >= 1.16`; earlier ruby_llm
  sent no `Authorization` header at all and could not reach Ollama Cloud.

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
