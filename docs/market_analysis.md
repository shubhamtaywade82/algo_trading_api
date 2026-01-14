# Market analysis (Telegram + AI) — NIFTY / SENSEX / Options

This app provides **AI-assisted market analysis** and **options-buying trade briefs** driven by Telegram commands.

At a high level:

- Telegram sends a webhook to Rails.
- Rails routes commands to a handler.
- The handler enqueues a background job.
- The job builds a **market snapshot** (spot candles + indicators + option-chain + India VIX).
- The snapshot is converted into a **prompt**.
- The prompt is sent to OpenAI and the response is posted back to Telegram.

This document explains the pipeline in detail for:

- **Index analysis** (NIFTY / BANKNIFTY / SENSEX)
- **Options buying setup** (NIFTY / BANKNIFTY / SENSEX)

---

## Architecture overview

### Entry point: Telegram webhook → command routing

- Telegram webhook route:
  - `POST /telegram/webhook` → `TelegramController#webhook` (`config/routes.rb`)
- Controller behavior:
  - Extracts `params[:message]` or `params[:edited_message]`
  - Normalizes `text` to lowercase
  - Calls `TelegramBot::CommandHandler.call(chat_id:, command: text)`

**Code references**

```1:13:/workspace/app/controllers/telegram_controller.rb
class TelegramController < ApplicationController
  def webhook
    payload = params[:message] || params[:edited_message]
    return head :ok unless payload

    chat_id = payload.dig(:chat, :id)
    text    = payload[:text].to_s.strip.downcase

    TelegramBot::CommandHandler.call(chat_id:, command: text)
    head :ok
  end
end
```

### Routing: Telegram command handler → background job

`TelegramBot::CommandHandler` is responsible for deciding what to do for each command:

- Market analysis commands (indices):
  - `/nifty_analysis`
  - `/bank_nifty_analysis`
  - `/sensex_analysis` (uses BSE)
- Options buying setup commands:
  - `/nifty_options`
  - `/banknifty_options`
  - `/sensex_options` (uses BSE)

All analysis commands enqueue `MarketAnalysisJob` and return immediately.

**Code references**

```23:137:/workspace/app/services/telegram_bot/command_handler.rb
def call
  case @cmd
  when '/nifty_analysis' then run_market_analysis('NIFTY')
  when '/sensex_analysis' then run_market_analysis('SENSEX', exchange: :bse)
  when '/bank_nifty_analysis' then run_market_analysis('BANKNIFTY')
  when '/nifty_options' then run_options_buying_analysis('NIFTY')
  when '/banknifty_options' then run_options_buying_analysis('BANKNIFTY')
  when '/sensex_options' then run_options_buying_analysis('SENSEX', exchange: :bse)
  else
    handled = try_manual_signal!
    TelegramNotifier.send_message("❓ Unknown command: #{@cmd}", chat_id: @cid) unless handled
  end
end
```

### Execution: background job → analysis service → LLM → Telegram

`MarketAnalysisJob`:

- Calls `Market::AnalysisService.call(symbol, exchange:, trade_type:)`
- Sends the AI answer back to Telegram (to the requesting `chat_id`)
- On error, sends a failure message to the same chat

**Code references**

```1:11:/workspace/app/jobs/market_analysis_job.rb
class MarketAnalysisJob < ApplicationJob
  queue_as :default

  def perform(chat_id, symbol, exchange: :nse, trade_type: nil)
    answer = Market::AnalysisService.call(symbol, exchange: exchange, trade_type: trade_type)
    TelegramNotifier.send_message(answer, chat_id: chat_id) if answer.present?
  rescue StandardError => e
    Rails.logger.error "[MarketAnalysisJob] ❌ #{e.class} – #{e.message}"
    TelegramNotifier.send_message("🚨 Error running analysis – #{e.message}", chat_id: chat_id)
  end
end
```

---

## What “market analysis” does (NIFTY / SENSEX / BANKNIFTY)

### 1) Instrument resolution

`Market::AnalysisService` starts by finding the `Instrument` row for the requested symbol.

Defaults:

- `segment: :index`
- `exchange: :nse` (except SENSEX which calls with `exchange: :bse`)

Lookup tries multiple columns to be forgiving:

- `underlying_symbol`
- `symbol_name`
- `trading_symbol`

If the instrument is missing, analysis is skipped and an error is logged.

### 2) Candle series + indicators

The service fetches intraday candles using:

- `instrument.candle_series(interval: ...)`

This is backed by the DhanHQ intraday OHLC endpoint and cached via `Rails.cache` per instrument + interval.

From the candle series, the snapshot includes:

- **OHLCV** for the latest candle (or previous candle if market is not live)
- **Bollinger bands** (period 20)
- **ATR-14**
- **RSI-14**
- **MACD**
- **EMA-14**
- **Supertrend signal**
- **20-bar range** high/low
- **Liquidity grab flags** up/down

### 3) Previous-day OHLC

The service fetches *previous trading day* OHLC using `instrument.historical_ohlc(...)` and caches it for 15 minutes.

This is used to give context in the AI prompt (and helps the model reason about gaps / range).

### 4) Option chain snapshot (for index options context)

Even for “index analysis”, the service includes an option-chain snapshot because the prompts are options-focused.

Flow:

- Determine expiry:
  - Use the requested `expiry:` override if supplied
  - Else use the “nearest expiry” (first element of `instrument.expiry_list`)
- Fetch option chain:
  - `instrument.fetch_option_chain(expiry)`
- Reduce the chain to 5 strikes around ATM:
  - `Market::OptionChainAnalyzer.new(raw, instrument.ltp).extract_data`
  - Picks:
    - `:atm`
    - `:itm_call`, `:otm_call`
    - `:itm_put`, `:otm_put`

This reduced chain is what gets shown in Telegram as the “snapshot”, and what gets embedded into the AI prompt.

### 5) India VIX + simple “regime flags”

The service also fetches India VIX via a dedicated `Instrument` record:

- `Instrument.find_by(security_id: 21)` (hard-coded)

Then it computes a small regime hint:

- IV@ATM (averaged from ATM CE/PE IV if available)
- Flags like `iv_high`, `iv_low`, `vix_high`, `vix_low`

These are meant as lightweight guidance for the prompt, not a full volatility model.

### 6) Prompt creation + OpenAI request

`Market::PromptBuilder.build_prompt(md, trade_type: ...)` converts the snapshot to a user prompt.

Then the service calls:

- `Openai::ChatRouter.ask!(prompt, system: Market::PromptBuilder.system_prompt(trade_type))`

The result is a **plain text** brief that is sent to Telegram.

---

## What “options buying setup” does (NIFTY / SENSEX / BANKNIFTY)

The options flow shares the same **data collection** pipeline as index analysis (candles, indicators, option-chain, VIX).

The main difference is **prompt variant + output expectations**.

### Command → trade_type mapping

- `/nifty_options` → `trade_type: :options_buying`
- `/banknifty_options` → `trade_type: :options_buying`
- `/sensex_options` (BSE) → `trade_type: :options_buying`

### Prompt variant and expected output

When `trade_type: :options_buying`:

- The system prompt stays the same “OptionsTrader-INDIA v1” desk persona.
- The user prompt asks for an “instant options buying trade”:
  - Prefer ATM / slightly ITM
  - Delta ≈ ±0.50 guidance
  - Use OI / IV context
  - Provide entry / SL / TP
  - Provide a “Decision Gate: BUY/AVOID – <reason>”

The prompt also includes bid/ask, OI, volume (where available) in the chain formatting, because execution quality matters more for a “buy now” setup.

---

## How to integrate SMC + AVRZ (5m + 15m) for better options suggestions + closing range

The current system prompt mentions “SMC-lite” and “VWAP/Anchored VWAP”, but the market snapshot (`md`) does **not** provide explicit market-structure levels or VWAP/AVWAP/zone levels. The AI therefore has to infer/hallucinate them, which reduces consistency.

To integrate **SMC + AVRZ** cleanly:

- compute **multi-timeframe** signals (5m trigger + 15m regime)
- add them to the snapshot (`md`)
- render them into the prompt so the model reasons from *actual* structure/value levels

### Goals

- **Options strike suggestion**: avoid buying into opposing structure; pick strikes aligned with 15m regime and confirmed by 5m structure break.
- **Intraday closing range**: derive a range from volatility *and* structure/value zones (not only ATR + Bollinger).

### Where it fits in the pipeline

- Data collection happens in `Market::AnalysisService#build_market_snapshot`.
- Prompt formatting happens in `Market::PromptBuilder.build_prompt`.

The integration should keep `Market::AnalysisService` thin by delegating calculations into focused classes.

### Step 1 — Add multi-timeframe candle series to the snapshot

Today the snapshot is built from a single interval (`DEFAULT_CANDLE = '15m'`). For SMC + AVRZ you want both:

- **5m**: entry/trigger timeframe (micro structure)
- **15m**: regime/structure timeframe (trend + larger zones)

Recommended snapshot shape (additive; keep existing keys for backward compatibility):

- `md[:timeframes][:m5]` and `md[:timeframes][:m15]`
  - each includes: `ohlc`, `atr`, `rsi`, `macd`, `supertrend`, `hi20`, `lo20`, `liq_up`, `liq_dn`

### Step 2 — Add a dedicated SMC analyzer (SMC-lite, intention-revealing outputs)

Create a focused class, e.g. `Market::SmcAnalyzer`, that takes a `CandleSeries` and returns a small hash of actionable structure data.

Avoid ambiguous names and “do everything” objects. This analyzer should return predictable keys, for example:

- **Trend/legs**
  - `:market_structure` → `:bullish | :bearish | :range`
  - `:last_swing_high`, `:last_swing_low`
- **Events**
  - `:last_bos` → `{ direction:, level:, ts: }` (or `nil`)
  - `:last_choch` → `{ direction:, level:, ts: }` (or `nil`)
- **Zones**
  - `:nearest_order_block` → `{ direction:, high:, low:, ts: }` (or `nil`)
  - `:nearest_fvg` → `{ direction:, high:, low:, ts: }` (or `nil`)
- **Liquidity**
  - `:buy_side_liquidity` / `:sell_side_liquidity` → arrays of levels or a nearest level + distance

Then attach per timeframe:

- `md[:smc][:m5] = Market::SmcAnalyzer.new(series_5m).call`
- `md[:smc][:m15] = Market::SmcAnalyzer.new(series_15m).call`

### Step 3 — Add VWAP/AVWAP + AVRZ (value zones) in a dedicated calculator

Create:

- `Market::VwapCalculator` (VWAP + anchored VWAP)
- `Market::AvrzCalculator` (builds the AVRZ bands)

Definitions used in this app:

- **VWAP**: session VWAP on the chosen timeframe
- **AVWAP**: VWAP anchored from a meaningful event
  - session open
  - IB start (if you add IB)
  - last BOS candle time (SMC-driven anchor)
- **AVRZ (Average Volatility Range Zone)**: a volatility-derived “fair value zone” around a VWAP/AVWAP center, adjusted by volatility regime

Recommended snapshot shape:

- `md[:value][:m5]  = { vwap:, avwap_open:, avwap_bos:, avrz: { mid:, low:, high:, width_points:, regime: } }`
- `md[:value][:m15] = { vwap:, avwap_open:, avwap_bos:, avrz: { mid:, low:, high:, width_points:, regime: } }`

AVRZ width policy (simple and explicit):

- `mid = avwap_open_15m` (fallback to `vwap_15m`)
- `base = atr_15m` (or `min(atr_15m, 0.75% of LTP)` if you want a clamp)
- widen/shrink based on `md[:regime]` (VIX/IV flags)
- final range can be “snapped” to nearby SMC levels (nearest liquidity pool / OB boundary) to respect structure

### Step 4 — Feed SMC + AVRZ into the prompt (stop making the model guess)

Update `Market::PromptBuilder` to print explicit sections such as:

- `=== 15m STRUCTURE (SMC) ===` (regime: structure, BOS/CHOCH, key zones, nearest liquidity)
- `=== 5m STRUCTURE (SMC) ===` (trigger: recent BOS/CHOCH, distances)
- `=== VALUE ZONES (VWAP/AVWAP/AVRZ) ===`
  - include `vwap`, `avwap_open`, `avwap_bos`, and `avrz low/mid/high` for both 5m and 15m

Then tighten the model instructions:

- **Options suggestion**
  - “Only recommend CE buys if 15m structure is bullish AND 5m has a bullish BOS/CHOCH confirmation, and price is above VWAP/AVWAP and not directly into a bearish OB/FVG.”
  - Equivalent rule for PE buys.
- **Closing range**
  - “Use AVRZ-15m as the primary close range; widen/shrink based on VIX regime; adjust to nearest structure levels.”

### Step 5 — Minimal tests (so the logic doesn’t rot)

Add focused specs with small fixtures / synthetic candles:

- `spec/services/market/smc_analyzer_spec.rb`
  - detects BOS/CHOCH and returns expected levels
- `spec/services/market/vwap_calculator_spec.rb`
  - VWAP/AVWAP math sanity (small arrays)
- `spec/services/market/avrz_calculator_spec.rb`
  - zone width changes with regime flags
- `spec/services/market/prompt_builder_spec.rb`
  - prompt includes the new “SMC” and “AVRZ” sections when fields exist

This keeps responsibilities explicit and makes future tuning safe.

### Persistence, expiry, and event-driven recompute (recommended design)

If you want SMC + AVRZ to be **consistent**, **auditable**, and **cheap to reuse** across Telegram commands / API calls, persist them as timeboxed “snapshots” per instrument + timeframe.

#### Persist as snapshots (single responsibility)

Create a dedicated model/table such as `MarketMetricsSnapshot` (name should communicate it’s *computed market state*, not orders/signals).

Recommended fields:

- **Identity**
  - `instrument_id`
  - `timeframe_minutes` (5 or 15)
  - `session_date` (IST trading day; resets VWAP/AVWAP)
  - `computed_at`
  - `source_candle_close_at` (the candle close the snapshot is based on)
- **Validity**
  - `expires_at` (time-based TTL)
  - `invalidated_at` (nullable)
  - `invalidated_reason` (nullable, string)
- **Payload** (store as jsonb to avoid schema churn while iterating)
  - `smc` (BOS/CHOCH, OB/FVG zones, liquidity levels, distances)
  - `value_zones` (VWAP, AVWAP anchors, AVRZ low/mid/high, widths)
  - `regime` (VIX/IV flags used to size zones)
  - `metadata` (version, inputs summary)

Recommended indexes:

- unique: (`instrument_id`, `timeframe_minutes`, `session_date`, `source_candle_close_at`)
- query: (`instrument_id`, `timeframe_minutes`, `expires_at`)

#### Expiry policy (simple + predictable)

Use candle-close TTLs:

- **5m** snapshot: `expires_at = source_candle_close_at + 5.minutes`
- **15m** snapshot: `expires_at = source_candle_close_at + 15.minutes`

Treat expiry as **soft**: a snapshot can become invalid **earlier** due to events (below).

Validity check:

- valid if `invalidated_at IS NULL` **and** `Time.current < expires_at`

#### Event-driven invalidation (don’t recompute “randomly”)

Persist market-structure/value events so recomputes are explainable. Create `MarketStructureEvent` (or equivalent) with:

- `instrument_id`, `timeframe_minutes`
- `event_at`
- `event_type` (e.g. `bos`, `choch`, `ob_touched`, `fvg_filled`, `avrz_break`, `session_reset`)
- optional `direction`, `level`/`zone` (jsonb)
- optional `snapshot_id` (which snapshot got invalidated)

When an event triggers:

- mark snapshot `invalidated_at = Time.current`, `invalidated_reason = <event_type>`
- write an event record
- enqueue a recompute job for the same timeframe (idempotent)

#### Recompute triggers (baseline + early)

Baseline (time-based):

- On every **5m candle close**, compute/persist the 5m snapshot for that close.
- On every **15m candle close**, compute/persist the 15m snapshot for that close.

Early recompute (event-based):

- **BOS/CHOCH** on that timeframe
- price **touches/consumes** the nearest OB/FVG zone (zone is “used up”)
- **AVRZ break** (candle close decisively outside band)
- **session reset** (new IST trading day → VWAP/AVWAP reset)

Practical coupling rule:

- A **15m BOS/CHOCH** should invalidate 15m and also trigger a fresh 5m snapshot (regime changed).

#### Runtime usage (get-or-build, then prompt)

In `Market::AnalysisService`, don’t compute SMC/AVRZ inline repeatedly. Prefer:

- fetch latest **valid** snapshots for 5m + 15m
- if missing/expired/invalidated → compute and persist for the latest closed candle
- inject into `md[:smc]` and `md[:value]`
- `Market::PromptBuilder` renders them

This keeps analysis deterministic (“same candle close → same snapshot”), and keeps Telegram analysis fast.

#### Scheduling it like `UpdateTechnicalAnalysisJob` (in-process loop)

This codebase already runs periodic technical-analysis updates via:

- `UpdateTechnicalAnalysisJob` (calls `Market::AnalysisUpdater.call`)
- `config/initializers/ta_scheduler.rb` which starts a loop thread after boot:
  - runs between `09:10` and `15:30` IST
  - enqueues `UpdateTechnicalAnalysisJob.perform_later`
  - sleeps `3.minutes`
  - guarded by `ENV['ENABLE_TA_LOOP'] == 'true'`

To schedule SMC+AVRZ snapshots the same way, mirror this pattern:

- **Job**: add a job like `UpdateSmcAvrzSnapshotsJob` that calls a single service, e.g. `Market::SmcAvrz::SnapshotUpdater.call`.
- **Initializer loop**: add a new initializer similar to `ta_scheduler.rb`:
  - guard with `ENV['ENABLE_SMC_AVRZ_LOOP'] == 'true'`
  - run only during market hours
  - **tick every 1 minute**
  - inside the updater, compute snapshots only when a new 5m/15m candle has *closed* (otherwise no-op)

Operational notes:

- This assumes a queue backend is running (e.g. delayed_job), because the loop uses `perform_later`.
- Make the updater idempotent (unique key on `instrument_id + timeframe + session_date + source_candle_close_at`) to avoid duplicate rows when multiple workers enqueue simultaneously.

#### Manual run (rake task pattern)

There is an existing rake entry point for TA:

- `rake technical_analysis:update` → `UpdateTechnicalAnalysisJob.perform_now`

For SMC+AVRZ you can mirror this for one-off runs/backfills:

- `rake market_metrics:update_smc_avrz` → `UpdateSmcAvrzSnapshotsJob.perform_now`

## Telegram commands (what users type)

### Index AI analysis (report comes later)

- **NIFTY**: `/nifty_analysis`
- **BANKNIFTY**: `/bank_nifty_analysis`
- **SENSEX**: `/sensex_analysis` (uses `exchange: :bse`)

Behavior:

- Bot replies immediately that analysis has started.
- A longer AI-generated report arrives later (via the job).

### Options buying setup (report comes later)

- **NIFTY**: `/nifty_options`
- **BANKNIFTY**: `/banknifty_options`
- **SENSEX**: `/sensex_options` (uses `exchange: :bse`)

Behavior:

- Bot replies immediately with a header like “Options Buying Setup”.
- The AI-generated trade brief arrives later (via the job).

### Manual signals (non-AI; triggers alert pipeline)

Separate from “market analysis”, the bot also supports “manual signals” to trigger the alert pipeline:

- `nifty ce`
- `banknifty pe`
- `sensex-ce`
- Slash variants also work, because the handler normalizes `/`, `_`, `-`:
  - `/banknifty_pe`

These commands do **not** call OpenAI. They create an `Alert` record (mimicking TradingView payload) and run the existing alert processor pipeline.

---

## LLM provider selection (OpenAI in prod, Ollama in local/dev)

All LLM calls go through `Openai::ChatRouter` (name kept for backward compatibility). It supports:

- **OpenAI** (default, recommended for production)
- **Ollama** via `ollama-client` (recommended for local/dev)

### Use Ollama locally (development)

1) Install and run Ollama locally:

- Ensure Ollama is running at `http://localhost:11434`
- Pull a model, e.g. `llama3.1`

2) Set env vars:

- `LLM_PROVIDER=ollama`
- `OLLAMA_BASE_URL=http://localhost:11434` (optional)
- `OLLAMA_MODEL=llama3.1` (optional)
- `OLLAMA_TIMEOUT=60` (optional)
- `OLLAMA_RETRIES=2` (optional)
- `OLLAMA_TEMPERATURE=0.2` (optional)

With `LLM_PROVIDER=ollama`, the OpenAI initializer is skipped and `OPENAI_API_KEY` is not required for boot.

### OpenAI behavior (default)

When using OpenAI, the router:

- Returns **plain text** (not JSON)
- Picks a default model by environment:
  - Production defaults to the “heavy” model
  - Non-production defaults to “light”
- Sends Telegram “typing” actions around the request (chat id defaults to `ENV['TELEGRAM_CHAT_ID']`)

---

## HTTP endpoints related to options analysis (non-Telegram)

These endpoints exist alongside Telegram, and they share the same underlying option-chain analyzer concepts.

### Market sentiment JSON

- `GET /market_sentiment?index=NIFTY&expiry=YYYY-MM-DD&strategy_type=intraday`

What it does:

- Fetches option chain for an index + expiry
- Computes IV rank and loads historical data
- Runs `Market::SentimentAnalysis` (which wraps `Option::ChainAnalyzer` for CE and PE)
- Returns bias/preferred signal + analysis details and suggested strategies

### Options analysis JSON

- `GET /options/analysis?index=NIFTY&instrument_type=ce&expiry=YYYY-MM-DD&strategy_type=intraday`

What it does:

- Fetches option chain + IV rank + historical data
- Runs `Option::ChainAnalyzer#analyze` for CE or PE
- Returns the analyzer result as JSON

---

## Operational prerequisites / configuration

### Required environment variables

Telegram:

- `TELEGRAM_BOT_TOKEN`
- `TELEGRAM_CHAT_ID` (used as fallback if `chat_id` not provided)

Broker/data:

- DhanHQ credentials (wherever your DhanHQ client expects them; see `lib/dhanhq/api.rb` and env usage)

### Required database seed/config

To analyze an index by symbol, `instruments` must include:

- A row for **NIFTY**, **BANKNIFTY**, and/or **SENSEX** with the correct:
  - `exchange` (`NSE` for NIFTY/BANKNIFTY, `BSE` for SENSEX)
  - `segment` (`index`)
  - `security_id` and `exchange_segment` mapping for DhanHQ
- A row for **India VIX** at:
  - `security_id: 21` (currently assumed by `Market::AnalysisService`)

If any of these are missing, analysis will be partial (no options/vix) or fail (instrument not found).

---

## Troubleshooting guide

- **“Instrument not found”**
  - The requested symbol isn’t in `instruments` for that exchange + segment.
  - Fix: import/seed instruments (see rake tasks under `lib/tasks/`).

- **“No option-chain data available.”**
  - Option chain API returned nil/empty or was filtered out.
  - The analysis still runs, but the prompt loses options context.

- **Telegram message truncated**
  - The notifier splits long messages into chunks of 4000 chars.
  - If formatting looks odd, the split likely happened mid-section.

- **AI response too generic / not tradeable**
  - Most often due to missing option chain data (no greeks/OI/IV) or stale candles.
  - Check: DhanHQ responses, `instrument.candle_series` interval caching, and whether markets are live.

