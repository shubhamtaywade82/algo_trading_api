# Crypto SMC/ICT scanner

Analysis-only scanner for **SOLUSDT** and **ETHUSDT** on Binance USD-M futures.
It reads price, looks for Smart Money Concepts / ICT setups across five
timeframes, and sends a Telegram message **only when a LONG or SHORT setup
clears every gate**. It places no orders, holds no API keys, and writes nothing
to the database.

The DhanHQ side of this app is untouched by all of it — different broker,
different market, no shared code path.

---

## What it looks for

Top-down, one question per timeframe:

| Timeframe | Question it answers | Feeds |
|---|---|---|
| `1d` | Which way is the market drawing? | directional bias |
| `4h` | Same, with more resolution | directional bias |
| `1h` | Is structure with us, and are we cheap? | bias + premium/discount |
| `15m` | Is there a POI, and was liquidity taken? | entry zone, stop anchor |
| `5m` | Has intent actually shown up? | **the trigger** |

### The primitives

- **Market structure** (`Smc::Structure`) — BOS (continuation) and CHoCH
  (reversal). A break is confirmed on a **close**, never a wick; a wick through
  a level that closes back inside is a sweep, which is the opposite signal.
- **Order blocks** (`Smc::OrderBlocks`) — the last opposing candle before the
  impulse that broke structure. Detection starts from the break and walks
  backwards, so a candle only qualifies if displacement actually followed it.
- **Fair value gaps** (`Smc::FairValueGaps`) — three-candle imbalances, filtered
  against ATR so dust is ignored. Tracked as tapped vs. fully filled.
- **Liquidity** (`Smc::Liquidity`) — equal highs/lows as pools, and sweeps of
  the *most recent* pivot. Taking out highs and rejecting is bearish; taking out
  lows and rejecting is bullish.
- **Premium / discount** (`Smc::PremiumDiscount`) — position in the dealing
  range, plus the 0.618–0.79 OTE band. Longs want discount, shorts want premium.
- **Price action** (`Smc::PriceAction`) — displacement, engulfing, rejection
  wicks. Confirmation only, weighted lightly.

Every threshold is ATR-relative, so one set of numbers works on a $4,000 ETH
candle and a $150 SOL candle.

### How a setup is scored

`SetupDetector` weights thirteen confluences to a total of 122, then normalises
to 100:

| Confluence | Weight | | Confluence | Weight |
|---|---|---|---|---|
| 1d aligned | 15 | | 15m POI active | 15 |
| 4h aligned | 15 | | 15m liquidity swept | 12 |
| 1h aligned | 10 | | **5m trigger** | **15** |
| 1h CHoCH | 6 | | 5m displacement | 5 |
| Premium/discount correct | 10 | | 5m imbalance | 5 |
| Price in OTE | 5 | | 5m engulfing/rejection | 4 |
| | | | Liquidity target beyond entry | 5 |

**Hard gates** — a setup is discarded unless all hold:

1. A 5m BOS or CHoCH in the trade's direction exists (no trigger, no trade).
2. The 1d and 4h biases do not *both* oppose the direction.
3. Score ≥ `CRYPTO_SMC_MIN_SCORE` (default 62).
4. Reward:risk to TP1 ≥ `CRYPTO_SMC_MIN_RR` (default 1.8).
5. The stop is no wider than `CRYPTO_SMC_MAX_STOP_ATR` × the 15m ATR.

Direction itself is a weighted vote (1d ×2, 4h ×2, 1h ×1) rather than a gate,
so a genuine 4h reversal is not discarded merely for disagreeing with a daily
trend it has just begun to end. It still loses the alignment points and has to
earn the score elsewhere.

### Levels

- **Entry** — the 5m close.
- **Stop** — beyond the furthest of {POI edge, swept level, recent 5m swing},
  plus 0.3 × the 5m ATR.
- **TP1** — the nearest 15m liquidity pool, floored at 1.5R.
- **TP2** — the 1h pool, floored at TP1 + 0.75R so the targets can never invert.

---

## Running it

Two triggers, one code path (`Crypto::Scanner`), so they cannot disagree about
what a setup is.

### Event-based (primary)

```bash
CRYPTO_SMC_ENABLED=true bundle exec rake crypto:stream
```

Opens one combined Binance WebSocket for every symbol × timeframe and scans the
moment a candle closes (`k.x`), because an SMC read is only meaningful on closed
candles. Reconnects with backoff — Binance drops a stream every 24h by design.

This process also carries a **safety-net scan every 5 minutes** for any symbol
the stream has not already covered. That is deliberate: this app has no
scheduler (Solid Queue's recurring tasks need `bin/jobs`, the deployed Active
Job adapter is `:async`, and there is no cron service), so the interval scan
lives with the listener rather than in a crontab that may not exist.

### Scheduled

`Crypto::SmcScanJob` runs the same sweep and is wired into `config/recurring.yml`
at five minutes, for deployments that *do* run the Solid Queue supervisor.

### One-off

```bash
rake crypto:config                 # show resolved settings
rake crypto:report SYMBOL=ETHUSDT  # full MTF read, no Telegram
rake crypto:scan                   # scan and alert now
rake crypto:scan SYMBOLS=SOLUSDT
```

`crypto:report` prints each timeframe's bias and the reason a chart did *not*
qualify — the first thing to reach for when the scanner seems too quiet.

### In-process

`CRYPTO_SMC_AUTOSTART=true` starts the listener in a thread inside the web
process (see `config/initializers/crypto_smc_scanner.rb`). Convenient on a
single-service deploy; note a multi-worker Puma opens one socket per worker.
They cannot double-alert — the cooldown is keyed on the setup, not the process —
but they do duplicate the Binance traffic. Prefer the dedicated process.

---

## Notifications

One message per setup, plain text so no level ever needs escaping:

```
🟢 LONG  SOLUSDT
SMC / ICT setup · grade A · score 79.5/100

🎯 Entry   152.345
🛑 Stop    148.900   (-2.26%)
✅ TP1     162.500   (6.67%)
✅ TP2     171.000   (12.24%)
⚖️ Risk    3.4450 per unit · R:R 2.95

🧭 Bias
1d ↑  4h ↑  1h ↑  15m ↑  5m ↑
Range: discount

📋 Confluence
• 1d structure bullish
• 15m unmitigated order block 149.900–151.500
• 15m sell-side liquidity swept at 149.100
• 5m BOS through 151.900

🕒 28 Jul 2026 14:35 IST
Analysis only — no order was placed.
```

**Suppression** is two-layered, because two processes can dispatch: an
in-process hash, plus a `Rails.cache` entry shared across processes. Both are
keyed on symbol + side + POI band and expire with
`CRYPTO_SMC_COOLDOWN_MINUTES` (default 45). Re-running the scan on an unchanged
chart is silent. The cache entry is a short-lived mutex, not a record — nothing
about the analysis is stored.

---

## Configuration

All settings live in `Crypto::Config`; see `.env.example` for the full list.
The important one is the master switch:

```bash
CRYPTO_SMC_ENABLED=false   # everything else is inert while this is false
```

Alerts go to `CRYPTO_TELEGRAM_CHAT_ID`, falling back to `TELEGRAM_CHAT_ID`.

### Geo-restriction

Binance returns **HTTP 451** to IPs in restricted regions, and many cloud
providers' US ranges are among them. If `rake crypto:scan` logs
`responded 451: Service unavailable from a restricted location`, the code is
fine and the egress IP is the problem. Point `CRYPTO_BINANCE_BASE` at a
reachable host, or run the scanner from a region Binance serves. The failure is
handled cleanly either way — `Analyzer` logs it and returns nil, so a blocked
region means no alerts rather than a crash.

---

## Design notes

- **No persistence.** Candles are fetched, analysed and dropped. There is no
  model, no migration, and no setup history — the Telegram message is the whole
  output.
- **No credentials.** `Crypto::Binance::Client` has no signed-request path at
  all, so it cannot place an order even if something asked it to.
- **`SmcScanJob` is not an `ApplicationJob`.** That base class mints a DhanHQ
  token before every perform and re-raises on failure, which would take the
  crypto scanner down whenever the Dhan session lapsed — an unrelated broker, in
  a market that is closed for most of the hours this job runs.
- **Retries are off.** By the time a retry landed, the 5m candle that triggered
  it would have been replaced; an alert on it would describe a chart that no
  longer exists. The next scan is the retry.
- **`Crypto::Candle` is not the app's `Candle`.** The latter rounds every price
  through `PriceMath.round_tick` (an NSE 0.05 tick) and casts volume with
  `to_i`. Both are wrong for a pair quoting three decimals with fractional
  volume.
