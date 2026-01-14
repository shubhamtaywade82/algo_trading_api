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

### Execution: background job → analysis service → OpenAI → Telegram

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

## OpenAI model selection and behavior

The OpenAI call is done through `Openai::ChatRouter` which:

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

