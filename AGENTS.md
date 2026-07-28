# AGENTS.md

## Cursor Cloud specific instructions

### Services overview

This is a **Rails 8 API-only** app (Ruby 3.3.4, PostgreSQL 16). No Redis or Sidekiq — background jobs use Delayed Job (`bundle exec rake jobs:work`). Standard commands are in `CLAUDE.md`.

### Starting services

1. **PostgreSQL** must be running before Rails boots: `sudo pg_ctlcluster 16 main start`
2. **Rails server**: `bundle exec rails server -p 5002`
3. **Delayed Job worker** (optional for most dev tasks): `bundle exec rake jobs:work`
4. Or use `bin/dev` which runs both web + worker via Foreman (`Procfile.dev`).

### Gotchas

- The `whenever` gem requires `cron` to be installed (`sudo apt-get install -y cron && sudo service cron start`). Without it, every Rails command prints a harmless but noisy error.
- `config/database.yml` uses peer auth by default (no password). The current PostgreSQL user must have a matching OS-level role — create one with `sudo -u postgres createuser -s $(whoami)` if missing.
- The dev database is `algo_trading_app_development`; test is `algo_trading_app_test`. Use `bin/rails db:prepare` to create + migrate in one step.
- External API keys (`DHAN_CLIENT_ID`, `TELEGRAM_BOT_TOKEN`, etc.) are optional — the app boots and tests pass without them. Trading operations just won't execute.
- 1 pre-existing RSpec failure in `spec/services/alert_processors/index_spec.rb:111` is known; it is not caused by environment setup.

### Lint / Test / Build

| Action | Command |
|--------|---------|
| Lint | `bundle exec rubocop` |
| Tests | `bundle exec rspec` |
| Single spec | `bundle exec rspec spec/path/file_spec.rb` |
| Dev server | `bundle exec rails server -p 5002` |
| Console | `bin/rails console` |


### Order placement invariant (must-follow)

- Route **all** live order placement through `Orders::Gateway`.
- `PLACE_ORDER` enforcement must live in the gateway; do not add new direct broker placement calls in other services.
- The gateway also gates on `LIVE_TRADING`, which the DhanHQ SDK (>= 2.7) requires for every order mutation.
- Any new order placement flow must return a dry-run/blocked response when either `PLACE_ORDER != "true"` or `LIVE_TRADING != "true"`, with logging.

---

### Rule Precedence Hierarchy (Must Follow for AI Agents & Tools)

1. **User Explicit Instructions**: Directly overrides generic defaults.
2. **Repository Project Rules (`AGENTS.md`, `CLAUDE.md`)**: Project invariants (e.g. `Orders::Gateway` invariant, RSpec testing) supersede external domain skills.
3. **Detected Repository Profile**: Existing architecture (PostgreSQL, Delayed Job, RSpec) overrides generic defaults (e.g. Solid Queue, Minitest).
4. **Team Conventions**: Defined architectural patterns.
5. **External Domain Skills (Rails-AI / GoF Patterns)**: Knowledge reference.

---

### Architecture & Refactoring Tools

Available executable analysis scripts in `bin/` or `.agents/skills/scripts/`:
- **Context Compiler**: `ruby .agents/skills/scripts/rails_context_compiler.rb <file_path>`
- **Prism AST Parser**: `ruby .agents/skills/scripts/ruby_prism_ast_analyzer.rb <file_path>`
- **Smell Detector**: `ruby .agents/skills/scripts/ruby_reek_smell_detector.rb <file_or_dir>`
- **Pattern Advisor**: `ruby .agents/skills/scripts/ruby_pattern_advisor.rb <file_or_dir>`
- **Project Profiler**: `ruby .agents/skills/scripts/rails_project_profiler.rb`

