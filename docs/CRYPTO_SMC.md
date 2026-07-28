# Crypto SMC/ICT scanner

Analysis-only scanner for **SOLUSDT** and **ETHUSDT** on Binance USD-M futures.
It reads price, looks for Smart Money Concepts / ICT setups across five
timeframes, and sends a Telegram message **only when a LONG or SHORT setup
clears every gate**. It places no orders, holds no API keys, and writes nothing
to the database.

The DhanHQ side of this app is untouched by all of it — different broker,
different market, no shared code path.

> **Status: off on the deployed app.** Binance answers `HTTP 451 — Service
> unavailable from a restricted location` to Render's egress IPs, so the
> scanner cannot fetch a candle from there. It is not deployed: the Render
> worker is commented out in `render.yaml`, the recurring entry is commented
> out in `config/recurring.yml`, and `CRYPTO_SMC_ENABLED` /
> `CRYPTO_SMC_AUTOSTART` both default to `false`. Run it from a machine
> Binance serves — see [Verifying it locally](#verifying-it-locally). Nothing
> here affects the DhanHQ services.

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

`Crypto::SmcScanJob` runs the same sweep. Its entry in `config/recurring.yml` is
**commented out** — see the status note at the top — and even uncommented it
needs a Solid Queue supervisor (`bin/jobs`, or `SOLID_QUEUE_IN_PUMA`) that this
deployment does not run. The job checks the data feed before scanning and
returns early if Binance is unreachable, so a blocked region produces one state
change alert rather than a scan that silently finds nothing.

### One-off

```bash
rake crypto:doctor                 # can we reach Binance? does Telegram work?
rake crypto:config                 # show resolved settings
rake crypto:report SYMBOL=ETHUSDT  # full MTF read, no Telegram
rake crypto:scan                   # scan and alert now
rake crypto:scan SYMBOLS=SOLUSDT
```

`crypto:report` prints each timeframe's bias and the reason a chart did *not*
qualify — the first thing to reach for when the scanner seems too quiet.

---

## Verifying it locally

The scanner needs no DhanHQ credentials, no market hours and no API key. It does
need a machine Binance will serve, which is the whole reason it is not deployed.

```bash
bundle install
bin/rails db:prepare          # Rails.cache is solid_cache, so the DB must be up
```

Put this in `.env` (see `.env.example` for the rest):

```bash
CRYPTO_SMC_ENABLED=true
CRYPTO_SMC_SYMBOLS=SOLUSDT,ETHUSDT
CRYPTO_TELEGRAM_CHAT_ID=<your chat id>
TELEGRAM_BOT_TOKEN=<your bot token>
# Optional — the analyst step. Follows LLM_BACKEND like every other caller.
CRYPTO_SMC_LLM=true
```

Then work up in four steps, each of which proves one thing:

**1. Is anything reachable?**

```bash
bin/rails crypto:doctor
```

Probes Binance with a real `/fapi/v1/ping` plus a two-candle fetch, prints the
endpoint, latency, last price and candle count, checks the Telegram
configuration, reports which LLM backend the analyst would use — and sends the
`✅ Binance connected` message to your chat, so you have confirmed the whole
delivery path before a single setup exists. `NOTIFY=false` skips the message.
Exits non-zero when Binance is unreachable.

A `451` here means the egress IP, not the code:

```
status:     ❌ Binance /fapi/v1/klines responded 451: Service unavailable from a restricted location
            HTTP 451 is a geo-block on this egress IP.
```

**2. What does the scanner actually see?**

```bash
bin/rails crypto:report SYMBOL=ETHUSDT
```

Prints every timeframe's bias, dealing-range zone and last structural event,
then either the setup or the reason there isn't one. No Telegram, no gates —
this is the view that explains a quiet scanner.

**3. Does an alert render and send?**

```bash
bin/rails crypto:scan SYMBOLS=SOLUSDT
```

Runs the real gates. Prints `telegram=sent` / `suppressed` / `unconfigured` per
symbol. Most of the time it will find nothing — that is correct behaviour, not a
failure. To see the message end to end without waiting for the market, drop
`CRYPTO_SMC_MIN_SCORE` and `CRYPTO_SMC_MIN_RR` temporarily:

```bash
CRYPTO_SMC_MIN_SCORE=1 CRYPTO_SMC_MIN_RR=0.1 bin/rails crypto:scan
```

Put them back afterwards — those thresholds are the difference between an alert
worth reading and a stream of noise.

**4. Does it run unattended?**

```bash
bin/rails crypto:stream
```

Opens the WebSocket, announces `✅ Binance connected` on startup, and scans on
every 5m/15m candle close. Leave it running; it should be silent until a setup
qualifies. `Ctrl-C` stops it.

Run the specs — they cover the detector, the analyst, the health probe and the
dispatcher without touching the network:

```bash
bundle exec rspec spec/services/crypto spec/jobs/crypto
```

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

### The execution plan

`Crypto::Analyst` writes the `🤖 Execution plan` block through
`Openai::ChatRouter`, so it follows `LLM_BACKEND` like every other LLM caller in
the app and needs no configuration of its own.

The division of labour is deliberately lopsided. `SetupDetector` decides
**whether** there is a trade — that stays arithmetic, reproducible and incapable
of hallucinating a confluence. The model only decides **how to describe taking
it**: entry, stop and targets are computed first and handed over as fixed facts
it is instructed never to alter, so the worst a bad generation can do is read
poorly. It cannot move a stop.

The prompt also carries the confluences that did *not* fire, which is what lets
the caveat be specific about a setup that scraped past the threshold rather than
generically hedged.

Every failure path returns nil and the alert sends with the levels alone — an
LLM outage must never cost a setup that already cleared every gate. It runs
inside `AlertDispatcher` *after* the cooldown check, so a suppressed duplicate
costs no round trip. `CRYPTO_SMC_LLM=false` turns it off entirely.

### Connectivity alerts

The scanner is silent by design, which makes an outage indistinguishable from a
quiet market: a scanner that has failed to fetch for six hours looks exactly
like one that has found nothing worth taking. `Crypto::Healthcheck` closes that
hole.

The probe is a real fetch — `/fapi/v1/ping` plus two candles — because a
reachable host returning no data is still a dead scanner. It reports on **state
change only**:

| Transition | Result |
|---|---|
| first ever probe | announce |
| ok → down, down → ok | announce |
| ok → ok, down → down | log only |
| `force: true` | announce regardless |

State is held in `Rails.cache` as well as in-process, so the scheduled job and
the stream runner do not each announce the same recovery. It runs at stream
startup (forced — starting the listener is the one moment someone is definitely
watching), on the stream's five-minute safety timer, at the head of every
`SmcScanJob`, and on demand via `rake crypto:doctor`. `CRYPTO_SMC_HEALTH_ALERTS=false`
silences the Telegram half; the logging happens either way.

```
✅ Binance connected
SOLUSDT · 5m · last 151.750
2 candles in 212ms · https://fapi.binance.com

Scanning SOLUSDT, ETHUSDT on 1d/4h/1h/15m/5m. You will hear from the
scanner again only when a setup qualifies.
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
