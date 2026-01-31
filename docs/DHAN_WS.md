# DhanHQ WebSocket — gem vs app listeners

This app uses the **DhanHQ** gem (dhanhq-client) for REST and WebSocket. Token and client_id come from the same place everywhere: **DB + DHAN_CLIENT_ID** (see `config/initializers/dhanhq.rb` and `docs/DHAN_AUTH.md`).

## Gem WS APIs (use these for new code)

The gem provides:

| API                                                                 | Purpose                                                                                                                                            |
| ------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| `DhanHQ::WS.connect(mode: :ticker \| :quote \| :full)`              | Market feed; yields normalized ticks. Uses `DhanHQ.configuration.resolved_access_token` and `client_id` (our initializer sets both from DB + env). |
| `DhanHQ::WS::Orders.connect { \|update\| ... }`                     | Real-time order updates.                                                                                                                           |
| `DhanHQ::WS::MarketDepth.connect(symbols: [...]) { \|depth\| ... }` | Market depth (bid/ask levels).                                                                                                                     |

### Configuration in this app

- **Token:** `config/initializers/dhanhq.rb` injects `access_token` from `DhanAccessToken.active` (DB). The gem’s WS client calls `resolved_access_token`, which uses that, so **no extra config** for token.
- **Client ID:** Same initializer sets `DhanHQ.configuration.client_id` from `DHAN_CLIENT_ID` or `CLIENT_ID`.

So any code that uses `DhanHQ::WS.connect`, `DhanHQ::WS::Orders.connect`, or `DhanHQ::WS::MarketDepth.connect` in this app automatically uses the same token and client_id as the rest of the app.

### Example: market feed with the gem

```ruby
# Uses token/client_id from our initializer (DB + DHAN_CLIENT_ID)
client = DhanHQ::WS.connect(mode: :full) do |tick|
  # tick: { kind: :full, segment: "IDX_I", security_id: "13", ltp: 24500.0, ... }
  Rails.logger.info "[WS] #{tick[:segment]} #{tick[:security_id]} LTP=#{tick[:ltp]}"
end

client.subscribe_one(segment: "IDX_I", security_id: "13")   # NIFTY
client.subscribe_one(segment: "IDX_I", security_id: "25")  # BANKNIFTY
# client.subscribe_many(list) for many instruments
# client.stop when done
```

### Example: order updates

```ruby
DhanHQ::WS::Orders.connect do |order_update|
  # process order_update
end
```

### Example: market depth

```ruby
DhanHQ::WS::MarketDepth.connect(symbols: [
  { symbol: "RELIANCE", exchange_segment: "NSE_EQ", security_id: "2885" }
]) do |depth_data|
  # process depth_data
end
```

See the gem’s docs for full options:

- `docs/rails_websocket_integration.md` (in the gem repo)
- `docs/websocket_integration.md`
- `docs/AUTHENTICATION.md` (dynamic token via `access_token_provider`)

## App listeners (FeedListener, DepthListener)

We still run **custom** listeners for the live feed and depth:

- **`Dhan::Ws::FeedListener`** — Connects to `wss://api-feed.dhan.co`, subscribes to NIFTY/BANKNIFTY and positions (RequestCode 17/21), and pushes raw packets to `FullHandler` and `QuoteHandler` (LTP cache, position analysis, order manager). Uses **same token/client_id** via `ws_token` and `ws_client_id` (DB + DHAN_CLIENT_ID).
- **`Dhan::Ws::DepthListener`** — Connects to depth WebSocket and parses binary depth packets. Same token/client_id source.

They are started when `ENABLE_FEED_LISTENER` or the depth flow is enabled (see `lib/feed/runner.rb`).

### Why keep them

- They drive **positions cache**, **FullHandler**/ **QuoteHandler**, and **Orders::Manager** with a **specific packet shape** (e.g. `exchange_segment` enum, `market_depth` array).
- The gem’s `DhanHQ::WS.connect` yields **normalized ticks** (e.g. `:segment` string, `:kind`); adapting those to our handlers would require an adapter layer.

So:

- **New features or standalone WS usage:** use the gem’s `DhanHQ::WS.connect`, `DhanHQ::WS::Orders.connect`, `DhanHQ::WS::MarketDepth.connect`; they already use the same token and client_id.
- **Existing feed/depth pipeline (positions, Full/Quote handlers):** keep using `Dhan::Ws::FeedListener` and `Dhan::Ws::DepthListener`; they use the same token/client_id and match the current handlers.

## Summary

| Use case                                       | What to use                                                                           | Token / client_id                      |
| ---------------------------------------------- | ------------------------------------------------------------------------------------- | -------------------------------------- |
| New market feed / order updates / depth        | `DhanHQ::WS.connect`, `DhanHQ::WS::Orders.connect`, `DhanHQ::WS::MarketDepth.connect` | From initializer (DB + DHAN_CLIENT_ID) |
| Existing feed (positions, Full/Quote handlers) | `Dhan::Ws::FeedListener`                                                              | Same (ws_token, ws_client_id)          |
| Existing depth (binary parser)                 | `Dhan::Ws::DepthListener`                                                             | Same                                   |

No separate WS credentials: **same env and DB token everywhere** (see `docs/DHAN_AUTH.md` and `.env.example`).
