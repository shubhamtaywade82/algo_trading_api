# Spec stubbing audit: external vs internal

This doc classifies what we stub in specs and recommends when to stub **external boundaries** vs **internal services**.

---

## Policy: run internal code to catch regressions

**Goal:** Specs should execute **real internal, non-dependent code** and stub **only external boundaries** (APIs, broker, Telegram, HTTP, time, etc.) so that when internal logic breaks, specs fail and regressions are caught.

- **Stub only external boundaries** when you want to test real internal behavior: broker (Dhan), Telegram, HTTP, DB (if needed), file system, time.
- **Do not stub internal services** that have no external dependencies (e.g. `Charges::Calculator`, pure domain logic). Let them run so changes to that logic cause spec failures.
- **Unit tests** that stub internal collaborators are still valid for “this unit calls this with these args,” but **prefer adding integration-style examples** (or refactoring) so that internal code runs and only external boundaries are stubbed.

---

## Guideline (unit vs integration)

- **Integration-style / behavior:** Stub **only** external boundaries; run **real** internal services. Use this where you want to catch regressions in internal logic.
- **Unit (isolation):** Stub collaborators (including internal services) to test one class in isolation. Keep these when you explicitly want “caller only” coverage; add integration-style examples alongside where regression coverage is needed.

---

## External boundaries (appropriate to stub)

These touch the outside world; stubbing them avoids real API calls, I/O, and non-determinism.

| Stub                                       | Used in                                                 | Purpose                 |
| ------------------------------------------ | ------------------------------------------------------- | ----------------------- |
| `Dhanhq::API::EDIS`, `Dhanhq::API::Orders` | `alert_processors/stock_spec`                           | Broker / eDIS           |
| `Dhanhq::API::Holdings`                    | `portfolio_insights/daily_reporter_job_spec`            | Broker holdings API     |
| `Dhanhq::API::Orders`                      | `integration/full_exit_flow_spec`                       | Broker orders           |
| `DhanHQ::Models::Position`                 | `positions/manager_spec`, `positions/active_cache_spec` | Broker positions        |
| `DhanHQ::Models::Order`                    | `orders/adjuster_spec`, `orders/executor_spec`          | Broker orders           |
| `TelegramNotifier`                         | job specs, etc.                                         | External notification   |
| `stub_request` (WebMock)                   | `orders/manager_spec`                                   | HTTP to Dhan / Telegram |
| `Rake::Task`                               | `levels_update_job_spec`                                | System boundary         |

---

## Internal services (currently stubbed)

These are app services that run in-process and do **not** call external systems by themselves. Stubbing them turns the spec into a **unit test** of the caller only.

| Stub                                                     | Used in                                      | Caller under test        | Effect                                                                     |
| -------------------------------------------------------- | -------------------------------------------- | ------------------------ | -------------------------------------------------------------------------- |
| `Market::AnalysisService`                                | `market_analysis_job_spec`                   | `MarketAnalysisJob`      | Job is tested; real analysis logic is not run.                             |
| `Option::ChainAnalyzer`, `Option::HistoricalDataFetcher` | `alert_processors/index_spec`                | `AlertProcessors::Index` | Index processor is tested; real chain/history logic is not run.            |
| `Option::StrategyExampleUpdater`                         | `update_strategy_examples_job_spec`          | Job                      | Job orchestration tested; real updater logic is not run.                   |
| `PortfolioInsights::Analyzer`                            | `portfolio_insights/daily_reporter_job_spec` | Job                      | Job tested; real analyzer logic is not run.                                |
| `Market::AnalysisUpdater`                                | `update_technical_analysis_job_spec`         | Job                      | Job tested; real updater logic is not run.                                 |
| `Orders::Analyzer`, `Orders::Manager`                    | `positions/manager_spec`                     | `Positions::Manager`     | Manager orchestration tested; real analyzer/manager logic is not run.      |
| `Orders::RiskManager`                                    | `orders/manager_spec`                        | `Orders::Manager`        | Manager orchestration tested; real risk logic is not run.                  |
| `Orders::Executor`, `Orders::Adjuster`                   | `orders/manager_spec`                        | (expectations only)      | Used to assert “Manager calls Executor/Adjuster when RiskManager says so.” |
| `Charges::Calculator`                                    | `orders/executor_spec`                       | `Orders::Executor`       | Executor tested; real charge calculation is not run.                       |

So **yes**: we stub internal workings (services that execute internally and don’t need external data by themselves). Those specs do **not** need external API/requests, but they also don’t run the real code of the stubbed services.

---

## Recommendations

1. **Keep the guideline explicit**
   - **Unit tests:** Stub collaborators (including internal services) to test one unit in isolation.
   - **Integration/behavior tests:** Stub **only** external boundaries (Dhan, Telegram, HTTP, etc.) and use **real** internal services so full flows are exercised.

2. **Where we already stub only external**
   - `alert_processors/stock_spec`: stubs `Dhanhq::API::EDIS` and `Orders` (external).
   - `orders/adjuster_spec`: stubs `DhanHQ::Models::Order` (external).
   - `positions/active_cache_spec`: stubs `DhanHQ::Models::Position` (external).

3. **Where we stub internal services**
   - **Jobs** (`market_analysis_job_spec`, `update_strategy_examples_job_spec`, `portfolio_insights/daily_reporter_job_spec`, `update_technical_analysis_job_spec`): they stub the internal service the job calls. To test “job + real analysis/updater” you’d keep stubbing Dhan/Telegram/HTTP only and let the internal service run.
   - **Positions::Manager**: stubs `Orders::Analyzer` and `Orders::Manager`. To test “manager + real analyzer + real orders manager” you’d stub only `DhanHQ::Models::Position` (and any HTTP/Telegram used downstream).
   - **Orders::Manager**: stubs `Orders::RiskManager`. To test “manager + real risk logic” you’d stub only HTTP (Dhan, Telegram) and use real `RiskManager`.

4. **Run internal code: plan** (to catch regressions)
   - **orders/executor_spec:** Add example that stubs only `DhanHQ::Models::Order` and `TelegramNotifier`, runs real `Charges::Calculator`, and asserts notification or net PnL reflects real charges. ✅ Done.
   - **market_analysis_job_spec:** Add example that stubs only Telegram (and any HTTP/candle source used by `Market::AnalysisService`), runs real `Market::AnalysisService`; requires DB/HTTP stubs for candles.
   - **portfolio_insights/daily_reporter_job_spec:** Add example that stubs only Dhan holdings + Funds + MarketFeed + Openai + Telegram, runs real `PortfolioInsights::Analyzer`. ✅ Done.
   - **update_technical_analysis_job_spec:** Add example that stubs only external (DB/HTTP if needed) + Telegram, runs real `Market::AnalysisUpdater`.
   - **update_strategy_examples_job_spec:** Add example that stubs only external, runs real `Option::StrategyExampleUpdater`.
   - **positions/manager_spec:** Add example that stubs only `DhanHQ::Models::Position`, `DhanHQ::Models::Order`, Telegram; runs real `Orders::Analyzer` and `Orders::Manager`. ✅ Done.
   - **orders/manager_spec:** Add example that stubs only HTTP (Dhan, Telegram), runs real `Orders::RiskManager`; Manager invokes Executor when take-profit is hit. ✅ Done.
   - **alert_processors/index_spec:** Add example that stubs only external (Dhan, HTTP for chain/history if any), runs real `Option::ChainAnalyzer` / `Option::HistoricalDataFetcher` where they don’t hit external; or stub at the HTTP boundary inside those services so internal logic runs.
   - Mark examples in spec files with a comment or tag (e.g. `# integration-style: runs real X, stubs external only`) so the intent is clear.

---

## Integration examples added (stub only external)

These specs now have an **integration** context that stubs **only** external boundaries and lets internal services run:

| Spec | Context | External stubs | Internal services that run |
|------|---------|----------------|----------------------------|
| `spec/jobs/portfolio_insights/daily_reporter_job_spec.rb` | `integration: stubs only external boundaries` | Holdings, Funds, MarketFeed, Openai, Telegram | `PortfolioInsights::Analyzer` |
| `spec/services/positions/manager_spec.rb` | `integration: stubs only external boundaries` | Position.all, Order.all/find, Telegram | `Orders::Analyzer`, `Orders::Manager` (incl. RiskManager, Executor dry_run) |
| `spec/services/orders/manager_spec.rb` | `integration: stubs only external boundaries` | HTTP (WebMock) Dhan + Telegram | `Orders::RiskManager`; Manager invokes Executor when TP hit |

Unit contexts are unchanged.

---

## Summary

- **Policy:** Specs should run **internal, non-dependent code** and stub **only external boundaries** so regressions are caught when internal logic breaks.
- **Current state:** Many specs stub internal services (unit style). That’s valid for isolation; we are adding **integration-style** examples that run real internal code and stub only external.
- **Plan:** See “Run internal code: plan” above. First item (executor + real `Charges::Calculator`) is done; others can be added incrementally.

---

## How to ask: use skills + keep RSpec and RuboCop clean

Use these prompts so the agent applies the **Ruby/Rails/RSpec skills** and verifies **RSpec** and **RuboCop** are clean. Respect the stubbing guideline above (external vs internal) when changing specs.

### 1. Prompt templates

**Review and fix with skills, then verify:**

- *“Use the **ruby** skill (solid, style, rails, rspec as relevant) to review [file or path]. List issues, fix them, then run `bundle exec rspec` and `bundle exec rubocop` for the changed files and fix until both pass with no failures / no offenses.”*
- *“Review and fix [path] using the Ruby and RSpec skills. After edits, run RSpec and RuboCop for the touched files and fix any failures or offenses. Do not change intentional stubbing of internal services (see docs/updates/SPEC_STUBBING_AUDIT.md).”*

**Target only specs:**

- *“Apply the **rspec** skill to [spec file or spec/...]. Fix layout, naming, and structure. Then run `bundle exec rspec path/to/spec` and `bundle exec rubocop path/to/spec` and fix until green and clean.”*

**Target only production code:**

- *“Apply **style** and **rails** skills to [file or app/...]. Fix issues, then run RuboCop on the changed files and fix offenses. Run related specs to confirm nothing broke.”*

**Full pass on a feature or directory:**

- *“Use the ruby skill to review and fix [e.g. app/services/alert_processors/]. List issues by category (style, rails, solid, rspec), fix them, run `bundle exec rspec spec/...` and `bundle exec rubocop app/... spec/...` and iterate until RSpec is green and RuboCop is clean.”*

### 2. Checklist for “skills + RSpec + RuboCop clean”

1. **Invoke the right skill** in your prompt (e.g. “use the ruby skill” or “apply rspec skill”).
2. **Review** the requested file(s) against the skill(s); list concrete issues.
3. **Fix** issues; avoid changing intentional internal stubbing (see stubbing audit above).
4. **Run RSpec** for the affected area:
   - `bundle exec rspec path/to/spec` or
   - `bundle exec rspec spec/unit/ spec/integration/` (adjust to your layout)
5. **Run RuboCop** on changed paths:
   - `bundle exec rubocop app/path/ spec/path/` or
   - `bundle exec rubocop -a app/path/ spec/path/` (auto-correct where safe)
6. **Re-run** after fixes until:
   - RSpec: no failures (and no pending you care about).
   - RuboCop: no offenses (or only explicitly allowed ones).

### 3. One-liner you can paste

```text
Use the ruby skill (solid, style, rails, rspec as relevant) to review and fix the code I’m working on. List issues, apply fixes, then run bundle exec rspec and bundle exec rubocop on the changed paths and fix until RSpec is green and RuboCop is clean. Do not change intentional stubbing of internal services (see docs/updates/SPEC_STUBBING_AUDIT.md).
```

Replace “the code I’m working on” with a path (e.g. `app/services/alert_processors/` or the open file) if you want a specific scope.
