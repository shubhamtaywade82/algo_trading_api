# Enhancements

## 🔧 1. Add Real-Time WebSocket Integration

**Goal**: Feed live LTP for all open positions and route them into exit logic in near real-time.

### Tasks

* [x] Implement a `Ws::TickerListener` using `faye-websocket` or `async-websocket`.
* [x] On startup, subscribe only to `securityIds` with open positions from `ActiveCache`.
* [x] Implement a dynamic re-subscriber when new positions are opened (`ActiveCache.refresh!` detects it).
* [x] Pipe live LTP to in-memory cache like `Rails.cache["ltp_#{securityId}"] = value`.
* [x] Modify `Orders::Analyzer` to prefer cached LTP over stale API fallback.

---

## 🎯 2. Enhance Exit Logic with Dynamic SL/TP Optimization

**Goal**: Optimize trailing and SL logic based on IV, trend score, and premium decay.

### Enhancements

* [ ] Add IV-based dynamic stop-loss width: high IV = looser SL, low IV = tighter.
* [ ] Introduce premium-decay-aware SL tightening as expiry nears.
* [ ] Include 5-min candle trend strength and OI-based confluence into `Analyzer` to drive adaptive exits.

---

## 🧠 3. Plug-in Technical and Option-Specific Indicators

**Goal**: Use momentum indicators, option OI/IV changes, and Greeks for smarter exits.

### Suggestions

* [ ] Add a `MarketContext::Fetcher` that pulls real-time Greeks, OI change, and PCR.
* [ ] Add `AnalyzerV2` or enhance current one to annotate:

  * Is this CE/PE seeing aggressive OI?
  * Is delta near exhaustion (e.g., nearing 0.9 or 0.1)?
  * Is gamma increasing → time for quick TP?

---

## 🔁 4. Add Event Queue / Streaming-Driven Flow

**Goal**: Eliminate polling from `Manager`, make system purely WebSocket-driven.

### Setup

* [ ] Introduce a `PositionChangeStream` (in-memory or file-based ring buffer).
* [ ] When `ltp` changes significantly, or new position is added:

  * Add it to the event stream.
  * `Orders::Manager` reads this and performs `Analyzer → RiskManager → Executor`.

---

## 🧪 5. Add Better Backtest + Simulation Harness

**Goal**: Offline test exit strategies for historical positions with replay of LTP + Analyzer metrics.

### Features

* [ ] `ExitSimulator.run(position_history, strategy: 'RiskManager')`
* [ ] Inject candle-by-candle price feed.
* [ ] Logs each exit signal, reason, and PnL over time for comparison.

---

## 🔒 6. Safety & Emergency Controls

**Goal**: Prevent capital erosion or strategy misfire.

### Controls

* [ ] Add circuit breaker: max drawdown per session/day.
* [ ] Exit all positions if unrealized losses breach ₹X.
* [ ] Add a “Manual override” toggle: pause automation instantly.

---

## 📈 7. Logging & Telemetry

**Goal**: Audit-grade trace of every step, exit, and price.

### Suggestions

* [ ] Use `ActiveSupport::Notifications` for all major actions (`:exit_triggered`, `:sl_adjusted`, `:tp_hit`)
* [ ] Log to a separate `ExitAudit` table for compliance & debugging.

---

## ✅ Immediate To-Do Checklist

| Task                                 | Status |
| ------------------------------------ | ------ |
| WebSocket `TickerListener`           | ☐      |
| Dynamic re-subscribe on new position | ☐      |
| IV & trend-based SL rules            | ☐      |
| Option Greeks + PCR integration      | ☐      |
| WebSocket event-based `Manager`      | ☐      |
| Exit backtester with LTP injection   | ☐      |
| Add safety circuit breakers          | ☐      |

---

AlgoTrading system will operate with near real-time reactivity, intelligent adaptive exits, and institutional safeguards—while staying lightweight and stateless (no Redis, no Sidekiq needed). Let me know which part you want to start implementing first, and I’ll generate complete, production-ready modules for it.
