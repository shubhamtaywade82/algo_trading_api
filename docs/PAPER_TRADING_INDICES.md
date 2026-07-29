# Paper trading the index watchlist

The app is signal-driven: something has to *send* a signal before anything
trades. Until now the only senders were the TradingView webhook and the
Telegram commands, so a deployment with nobody pushing alerts sat idle no
matter what the trading flags said.

This adds a third sender that runs on its own — a scan loop over a watchlist of
indices — and points the whole thing at the simulated book.

## The shape of it

```
live:paper_engine (one worker process)
  │
  ├─ Live::MarketFeedHub ── ticks ─→ Live::TickCache
  │                              └─→ Paper::Exchange.process_tick
  │                                    fills resting orders, marks positions,
  │                                    drives DayRollover / EodSquareOff
  │
  └─ every INDEX_WATCHLIST_SCAN_SECONDS, during the session:
       Market::AnalysisUpdater
         └─ per symbol: fetch 5m candles → Market::ConfluenceDetector
              ├─ Market::ConfluenceNotifier  → Telegram (unchanged)
              └─ Market::ConfluenceTrader    → Alert
                   └─ AlertProcessorFactory → AlertProcessors::Index
                        └─ Orders::Gateway → Paper::Broker → Paper::Exchange
```

`ConfluenceTrader` is a signal *source*, not a second execution path. It builds
an `Alert` and hands it to `AlertProcessorFactory` exactly as the webhook does,
so strike selection, affordability, sizing, super-order legs, risk management
and exits are the code that was already there and already tested. Nothing in
the new code talks to a broker or to `Paper::Exchange` — whether the order is
simulated stays the gateway's decision, read from `PAPER_TRADING`.

## Why one process

`Live::TickCache` is a process-local Hash, and that is deliberate (see the
measurement in `CLAUDE.md`). In paper mode the tick stream is the matching
engine's clock: it fills resting orders, marks positions, trails super-order
stops, and lazily runs `Paper::DayRollover` and `Paper::EodSquareOff`. Split
the scanner and the feed across two processes and the scanner places orders
that nothing ever fills.

The web service cannot host the feed either — Puma runs `WEB_CONCURRENCY=2`
forks and each would open its own WebSocket to Dhan. Hence a dedicated worker
that owns both halves.

The web service still has `PAPER_TRADING=true` so that a TradingView webhook or
a Telegram signal books into the *same* paper account rather than being dropped
by `PLACE_ORDER=false`. Orders it places rest in the database until the engine's
tick loop fills them, which works because `Paper::Exchange.process_tick` reads
the book from the database rather than from memory.

## The gates

`ConfluenceTrader` applies these in order, and logs the reason when it declines:

| Gate | Env | Default |
|---|---|---|
| Master switch | `INDEX_WATCHLIST_TRADING` | `false` |
| Symbol is on the roster | `INDEX_WATCHLIST` | `NIFTY,BANKNIFTY,SENSEX` |
| Conviction floor | `INDEX_WATCHLIST_MIN_LEVEL` | `high` (8 of 14 factors) |
| Trading day, 09:20–15:00 IST | — | — |
| Per-symbol quiet period | `INDEX_WATCHLIST_COOLDOWN_MINUTES` | `30` |
| Per-symbol daily cap | `INDEX_WATCHLIST_MAX_TRADES_PER_DAY` | `3` |

The window closes at 15:00 because `Paper::EodSquareOff` closes INTRADAY at
15:15 — a 15:05 entry would be bought and closed within ten minutes. It opens
at 09:20 because the opening range is noise and the 5-minute candles the score
is computed on have barely formed.

## When it is allowed to trade

`MarketCalendar.market_open?` is the single definition of "the market is open":
**a weekday, not on the holiday list, between 09:15 and 15:30 IST.** Everything
that gates on the session reads it — `Orders::PlaceOrderGuard` on the live
path, `Paper::Exchange` on the simulated one, the MCP status tool, and the
scanner. It converts the time to IST rather than assuming the caller is already
there, so it is correct on Render's UTC hosts.

Three layers apply, narrowest first:

| Layer | Window | Applies to |
|---|---|---|
| `ConfluenceTrader` entry window | 09:20–15:00 IST, trading days | new entries from the scanner |
| `MarketCalendar.market_open?` | 09:15–15:30 IST, trading days | every order, from any source |
| `live:paper_engine` scan loop | 09:15–15:30 IST, trading days | whether the scan runs at all |

So: nothing is entered before 09:20 or after 15:00, nothing at all is placed
outside 09:15–15:30, and neither happens on a Saturday, a Sunday, or a listed
market holiday. Outside the session the engine keeps the feed up and reports
health but makes no REST calls — a reconnect out of hours is cheaper than a
cold start at 09:15.

The one deliberate exception is a `force: true` order, which waives the
market-hours check. That is how `Paper::EodSquareOff` closes intraday
positions at 15:15 and how an operator flattens the book after the bell — a
square-off that could not run after the close would leave the position it was
meant to close.

`Paper::Exchange` used to carry its own copy of this check that tested the
weekday but not the holiday list, so an order placed on a weekday holiday —
Gandhi Jayanti 2026 is a Friday — was accepted and filled against a stale
cached price. It now delegates like everything else.

The cooldown and the daily cap are belt and braces over `ConfluenceDetector`'s
own 45-minute cooldown and state-change gate. That one is keyed on the *signal*
and lives in `Rails.cache`, so a process restart mid-session repopulates it from
scratch; these are keyed on an order actually being placed.

A `skipped` or `failed` alert does not consume the daily budget — the processor
declined it on its own analysis and nothing was placed.

## Capital

`PAPER_CAPITAL` sets the book's starting capital in rupees. It is read **only
when the account row is first created**: silently re-capitalising a running
book on every boot would rewrite the denominator of every P&L number it has
already produced.

To change the capital of a book that already exists:

```bash
rails live:paper_capital CAPITAL=100000
```

That is destructive by design — it clears positions and orders, because a book
holding positions sized against the old capital is not comparable to one
starting fresh at the new figure.

The deployment sets `PAPER_CAPITAL=100000` (₹1 lakh). At that balance the
capital bands in the README put allocation at 30%, risk per trade at 5% and the
daily loss cap at 5%, so the sizing the index processor does is unchanged — it
just works from a smaller number.

## Running it

Locally:

```bash
PAPER_TRADING=true PAPER_CAPITAL=100000 INDEX_WATCHLIST_TRADING=true \
  rails live:paper_engine
```

The engine refuses to start unless `PAPER_TRADING` is on — it places orders on
its own initiative and must never be one environment variable away from doing
that live. `PAPER_ENGINE_ALLOW_LIVE=true` is the deliberate override and is set
nowhere in this repo.

Inspecting the book, from any process:

```bash
rails live:paper_book      # positions, working orders, P&L summary
rails live:paper_eod       # force the 15:15 square-off
rails live:paper_roll      # force the day rollover
rails live:paper_reset     # back to starting capital
```

## When the engine shows no logs at all

An empty log is ambiguous — it is produced by a worker that never existed, by
one that crashed before writing, and by one that is running perfectly. Work
through it in this order rather than assuming the engine is dead.

**1. Does the service exist on Render?** Declaring `algo_trading_paper_engine`
in `render.yaml` does not create it. A push auto-deploys the services that
already exist; a service that is new in the blueprint is only created when the
blueprint is synced from the dashboard (Blueprints → this blueprint → Sync).
Before the sync there is no worker, no build, and no log stream — the dashboard
shows nothing, which reads exactly like a service that started and stayed
quiet. Check the service list before reading anything into an empty log.

**2. Did it abort on boot?** Both abort paths — `PAPER_TRADING` not set, and a
token that could not be minted — write to stderr, which is never buffered, so
they appear immediately. Seeing one means the service exists and only its
environment is wrong. Every `DHAN_*` key is `sync: false` and services do not
share environment, so the values set on the web service are not visible on the
worker; missing `DHAN_CLIENT_ID` / `DHAN_PIN` / `DHAN_TOTP_SECRET` make
`ENV.fetch` raise inside `start_token_refresher` and abort the process.

**3. Is it running but buffered?** This was the original failure. Ruby leaves
`$stdout` block-buffered whenever it is not a TTY, and on Render logs are
captured through a pipe. The buffer flushes at 8 KB or on exit, and the engine
is a daemon that does neither during a session: at a ~75-byte heartbeat every
180s it needs roughly 5.5 hours to fill 8 KB — longer than the 6h15m session —
so a healthy engine logged nothing all day. Puma sets sync itself, which is why
the web service was never affected and this stayed invisible until the first
rake worker was deployed.

`config/environments/production.rb` and the daemon tasks in
`lib/tasks/live_feed.rake` now set `$stdout.sync = true`, so a running engine
prints its `[engine] connected=… ticks=… open=… net_pnl=…` heartbeat every
`INDEX_WATCHLIST_SCAN_SECONDS`. That line appears outside market hours too —
the scan is session-gated but the health report is not — so silence during the
session now means the process really is not running.

## Turning it off

Set `INDEX_WATCHLIST_TRADING=false` on the engine worker. The feed, the book,
the analysis and the Telegram alerts all keep running; the scanner simply stops
placing anything. Suspending the worker stops the scan and the fills, but any
open paper position stays in the database and is picked up when it comes back.

## What did not change

- No new order path. `Orders::Gateway` is still the only way an order is
  placed, and `PLACE_ORDER` / `LIVE_TRADING` are still `false` everywhere.
- No scheduler. `config/recurring.yml` is still empty and `config/schedule.rb`
  is still commented out; the engine's loop is its own clock, like
  `crypto:stream`.
- `Watchlist` / `WatchlistItem` still hold the equity universe that
  `Watchlists::RefreshService` rebuilds. The index roster is a constant plus an
  env var, because three symbols that change about never do not need a table, a
  migration and a "scanner traded nothing because the row was missing" failure
  mode.
