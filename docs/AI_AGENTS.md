# AI Agents Orchestration Layer

The app includes an **AI agents orchestration layer** for trading intelligence: market analysis, options flow, trade proposals, position review, and operational Q&A. It uses the [chatwoot/ai-agents](https://github.com/chatwoot/ai-agents) gem.

**Critical boundary:** The AI layer only **analyzes and proposes**. It **never** places orders. Execution always goes through the deterministic `Strategy::Validator` gate and your existing order pipeline (e.g. `Orders::Executor`).

---

## Table of contents

- [Quick start](#quick-start)
- [Configuration](#configuration)
- [HTTP API](#http-api)
- [In-app usage (Ruby)](#in-app-usage-ruby)
- [Proposal validation](#proposal-validation)
- [Architecture](#architecture)

---

## Quick start

1. **Install dependencies**
   ```bash
   bundle install
   ```

2. **Set LLM provider**
   - **OpenAI:** `OPENAI_API_KEY=sk-...`
   - **Ollama (local):** `OPENAI_URI_BASE=http://localhost:11434/v1` and optionally `OPENAI_OLLAMA_MODEL=qwen3:latest`

3. **Optional: protect the API**
   - Set `AI_AGENTS_ACCESS_TOKEN` to a secret value.
   - Send `Authorization: Bearer <token>` on every request. If the env var is blank, no auth is enforced.

4. **Start the app**
   ```bash
   bundle exec rails server -p 5002
   ```

5. **Call the API**
   ```bash
   curl -s -X POST http://localhost:5002/ai_agents/analyze \
     -H "Content-Type: application/json" \
     -d '{"symbol":"NIFTY","candle":"15m"}'
   ```

---

## Configuration

### Initializer

`config/initializers/ai_agents.rb` configures the ai-agents gem.

| Setting            | Source / default | Description |
|--------------------|------------------|-------------|
| Provider           | `OPENAI_API_KEY` or `ANTHROPIC_API_KEY` | Default provider `:openai`; Anthropic if key present. |
| Model              | `OPENAI_URI_BASE` + env | If URL contains `11434`, uses Ollama and `OPENAI_OLLAMA_MODEL` (default `qwen3:latest`). Else production: `gpt-4o-mini`, dev: `gpt-4o`. |
| `max_turns`        | `10`             | Max conversation turns per run. |
| `debug`            | `Rails.env.development?` | Verbose logging. |

### Environment variables

| Variable                 | Required | Description |
|--------------------------|----------|-------------|
| `OPENAI_API_KEY`         | Yes*     | OpenAI API key. *Not needed if using Ollama only.* |
| `OPENAI_URI_BASE`        | No       | Override API base URL (e.g. Ollama `http://localhost:11434/v1`). |
| `OPENAI_OLLAMA_MODEL`    | No       | Ollama model name when `OPENAI_URI_BASE` points to Ollama (default `qwen3:latest`). |
| `ANTHROPIC_API_KEY`      | No       | If set, enables Anthropic as an alternative provider. |
| `AI_AGENTS_ACCESS_TOKEN` | No       | If set, all `/ai_agents/*` requests must send `Authorization: Bearer <this value>`. |

---

## HTTP API

Base path: **`/ai_agents`**.

### Authentication

- If `AI_AGENTS_ACCESS_TOKEN` is set: send `Authorization: Bearer <token>` on every request. Mismatch → `401 Unauthorized`.
- If unset: no auth check; all requests are allowed.

### Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/ai_agents/analyze` | Market structure + options flow for a symbol. |
| `POST` | `/ai_agents/propose` | Full trade proposal pipeline (strike, entry, SL, target). |
| `POST` | `/ai_agents/ask` | Free-form operational/debug question. |
| `GET`  | `/ai_agents/positions` | Review open positions (P&L, risk, exit suggestions). |
| `GET`  | `/ai_agents/session_report` | Combined analysis + positions + proposal for a symbol. |

### Request / response reference

#### POST /ai_agents/analyze

**Body (JSON):**

| Field   | Type   | Required | Default | Description |
|---------|--------|----------|---------|-------------|
| `symbol`| string | Yes      | —       | NSE index symbol (e.g. `NIFTY`, `BANKNIFTY`). |
| `candle`| string | No       | `15m`   | Timeframe for candle data. |

**Response:** `{ "output": "<analysis text>", "context": { ... } }`

**Example:**
```bash
curl -s -X POST http://localhost:5002/ai_agents/analyze \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{"symbol":"NIFTY","candle":"15m"}'
```

---

#### POST /ai_agents/propose

**Body (JSON):**

| Field      | Type   | Required | Description |
|------------|--------|----------|-------------|
| `symbol`   | string | Yes      | NSE index symbol. |
| `direction`| string | No       | Hint: `CE` or `PE`. Omit for auto. |

**Response:**
```json
{
  "output": "<narrative>",
  "proposal": { "symbol", "direction", "strike", "entry_price", "stop_loss", "target", "quantity", ... },
  "validation": { "valid": true/false, "errors": [], "warnings": [] },
  "ready_to_trade": true/false,
  "context": { ... }
}
```

- `proposal`: Parsed trade hash, or `null` if none could be extracted.
- `validation`: Result of `Strategy::Validator.validate(proposal)`. Only treat as executable when `validation.valid === true`.
- `ready_to_trade`: Convenience flag: `proposal` present and `validation.valid === true`.

**Example:**
```bash
curl -s -X POST http://localhost:5002/ai_agents/propose \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{"symbol":"NIFTY","direction":"CE"}'
```

---

#### POST /ai_agents/ask

**Body (JSON):**

| Field     | Type   | Required | Description |
|-----------|--------|----------|-------------|
| `question`| string | Yes      | Natural language question (e.g. “Why did trade #214 exit early?”). |

**Response:** `{ "answer": "<text>", "context": { ... } }`

**Example:**
```bash
curl -s -X POST http://localhost:5002/ai_agents/ask \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{"question":"Why did trade #214 exit early?"}'
```

---

#### GET /ai_agents/positions

No body. Returns position review (P&L, risk, exit suggestions).

**Response:** `{ "answer": "<text>", "context": { ... } }`

**Example:**
```bash
curl -s http://localhost:5002/ai_agents/positions \
  -H "Authorization: Bearer YOUR_TOKEN"
```

---

#### GET /ai_agents/session_report

**Query:**

| Param   | Type   | Default  | Description |
|---------|--------|----------|-------------|
| `symbol`| string | `NIFTY`  | NSE index symbol. |

**Response:**
```json
{
  "symbol": "NIFTY",
  "timestamp": "2025-03-12T...",
  "analysis": "<market analysis text>",
  "positions": "<position review text>",
  "proposal": { ... },
  "validation": { "valid", "errors", "warnings" },
  "context": { ... }
}
```

**Example:**
```bash
curl -s "http://localhost:5002/ai_agents/session_report?symbol=BANKNIFTY" \
  -H "Authorization: Bearer YOUR_TOKEN"
```

---

## In-app usage (Ruby)

Single entry point: **`AI::TradeBrain`**. All methods return either an `Agents::RunResult` (with `.output` and `.context`) or a hash for `propose` / `session_report`.

### Market analysis

```ruby
result = AI::TradeBrain.analyze("NIFTY", candle: "15m")
puts result.output

# Multi-turn: pass context from a previous call
result2 = AI::TradeBrain.analyze("NIFTY", context: result.context)
```

### Trade proposal

```ruby
data = AI::TradeBrain.propose(symbol: "NIFTY", direction: "CE")  # direction optional

puts data[:output]
proposal   = data[:proposal]    # Hash or nil
validation = data[:validation] # { valid:, errors:, warnings: }

# Only execute if the deterministic validator allows it
if data[:proposal].present? && Strategy::Validator.valid?(data[:proposal])
  # Orders::Executor.place(data[:proposal])  # when wired
end
```

### Position review

```ruby
result = AI::TradeBrain.review_positions
puts result.output
```

### Operational Q&A

```ruby
result = AI::TradeBrain.ask("Why did trade #214 exit early?")
puts result.output
```

### Quick analysis (single agent, lighter)

```ruby
result = AI::TradeBrain.quick_analysis("NIFTY")
puts result.output
```

### Session report (analysis + positions + proposal)

```ruby
report = AI::TradeBrain.session_report("NIFTY")
# report[:analysis], report[:positions], report[:proposal], report[:validation], report[:context]
```

---

## Proposal validation

**`Strategy::Validator`** is the gate between AI proposals and order execution. It is deterministic (no DB, no external APIs).

### Required proposal fields

- `symbol`, `direction`, `strike`, `entry_price`, `stop_loss`, `target`
- `direction`: `CE` or `PE`
- Numeric rules: entry in range, SL < entry < target, quantity > 0, strike > 0, risk-reward ≥ 1.5, optional confidence ≥ 0.6, optional `risk_approved == true`

### Usage

```ruby
# Boolean
Strategy::Validator.valid?(proposal)   # => true / false

# Full result
result = Strategy::Validator.validate(proposal)
# => { valid: true/false, errors: [...], warnings: [...] }
```

Always validate `data[:proposal]` with `Strategy::Validator` before passing it to any execution path.

---

## Architecture

### Entry points

- **HTTP:** `AiAgentsController` → `AI::TradeBrain` → runners/agents.
- **Ruby:** Call `AI::TradeBrain` directly.

### Runners (`app/ai/runners/`)

| Runner           | Use case        | Agents involved |
|------------------|-----------------|-----------------|
| `MarketRunner`   | Analyze         | Market structure + options flow |
| `TradeRunner`    | Propose         | Supervisor → MarketStructure, OptionsFlow, TradePlanner, Risk |
| `OperatorRunner` | Ask / positions | Operator agent + tools |

### Agents (`app/ai/agents/`)

- **SupervisorAgent** — Entry and routing for the trade pipeline.
- **MarketStructureAgent** — Market structure analysis.
- **OptionsFlowAgent** — Options flow analysis.
- **TradePlannerAgent** — Trade setup (strike, entry, SL, target).
- **RiskAgent** — Risk validation; can set `risk_approved` on proposals.
- **OperatorAgent** — Q&A and position review.

### Tools (`app/ai/tools/`)

Agents use these to fetch data (read-only): backtest, Dhan candles, funds, market sentiment, option chain, positions, trade log. Implementations live under `app/ai/tools/`.

### Flow summary

1. **Analyze:** `TradeBrain.analyze` → `MarketRunner` → market + options agents → text + context.
2. **Propose:** `TradeBrain.propose` → `TradeRunner` → supervisor + specialists → text; `TradeRunner.extract_proposal` parses JSON from output; `Strategy::Validator.validate(proposal)` returns validation.
3. **Ask / positions:** `TradeBrain.ask` / `review_positions` → `OperatorRunner` → operator agent + tools → text + context.

For day-to-day use, call **`AI::TradeBrain`** or the **HTTP endpoints**; only extend or debug by touching agents/runners/tools directly.
