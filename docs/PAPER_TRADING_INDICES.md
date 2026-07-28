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
