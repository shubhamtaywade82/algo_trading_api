#!/usr/bin/env bash
#
# Render build command.
#
# This runs on every deploy, so it has to be correct in all of these cases and
# not just the happy one:
#
#   * first ever deploy       — database exists but is empty, no schema at all
#   * routine redeploy        — schema present, some migrations pending
#   * no-op redeploy          — nothing to migrate, nothing to seed
#   * database still waking   — managed instance not accepting connections yet
#   * optional data missing   — instrument import fails, app should still ship
#
# The previous version ran `db:migrate` directly and aborted the whole build on
# any failure, so a cold database or a transient network blip failed the deploy.
set -euo pipefail

: "${RAILS_ENV:=production}"
export RAILS_ENV

log()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m⚠ %s\033[0m\n' "$*"; }
ok()   { printf '\033[32m✔ %s\033[0m\n' "$*"; }

# Runs a command, retrying with exponential backoff. Used for anything that
# touches the database: a managed instance can refuse connections for the first
# few seconds after it wakes, which is not a reason to fail a deploy.
retry() {
  local attempts=$1 description=$2; shift 2
  local attempt=1 delay=2

  until "$@"; do
    if (( attempt >= attempts )); then
      printf '\033[31m✖ %s failed after %d attempts\033[0m\n' "$description" "$attempts"
      return 1
    fi
    warn "$description failed (attempt ${attempt}/${attempts}); retrying in ${delay}s"
    sleep "$delay"
    attempt=$(( attempt + 1 ))
    delay=$(( delay * 2 ))
  done
}

# For steps whose failure should be reported but must not fail the deploy.
optional() {
  local description=$1; shift
  if "$@"; then
    ok "$description"
  else
    warn "$description failed — continuing. Re-run it from the Render shell once resolved."
  fi
}

# `bin/rails` rather than `bundle exec rails`: the gem binstubs check bin/bundle,
# which is not how Render lays out the bundle.
rails() { ruby bin/rails "$@"; }

# ── Preflight ───────────────────────────────────────────────────────────────
# Fail here with something readable rather than 200 lines into a stack trace.
log "🔍 Environment"
echo "   ruby        $(ruby -v | awk '{print $2}')"
echo "   RAILS_ENV   ${RAILS_ENV}"

if [ -z "${DATABASE_URL:-}" ]; then
  printf '\033[31m✖ DATABASE_URL is not set.\033[0m\n'
  echo '  Attach a database in render.yaml (fromDatabase) or set it manually.'
  exit 1
fi
# Print the host only. The URL carries credentials and build logs are retained.
echo "   database    $(printf '%s' "$DATABASE_URL" | sed -E 's#^[^:]+://[^@]*@##; s#/.*$##')"

if [ -z "${SECRET_KEY_BASE:-}" ]; then
  warn 'SECRET_KEY_BASE is not set; Rails will refuse to boot in production.'
fi

# ── Dependencies ────────────────────────────────────────────────────────────
log "📦 Installing dependencies"
bundle install
ok "gems installed"

# ── Database ────────────────────────────────────────────────────────────────
# `db:prepare`, not `db:migrate`. On an empty database migrate assumes a schema
# that is not there; prepare creates the database if it is missing, loads
# db/schema.rb when there is nothing to migrate from, and otherwise runs the
# pending migrations. It is a no-op when the schema is already current, which
# is what makes it safe to run on every redeploy.
log "🛠  Preparing database"
retry 5 "database preparation" rails db:prepare
ok "schema is current"

# ── Seeds ───────────────────────────────────────────────────────────────────
# db/seeds.rb skips anything already present, so this is safe to repeat. Set
# SKIP_SEEDS_ON_DEPLOY=true to opt out; the old flag defaulted to *not* seeding,
# which left a first deploy with no strategy catalogue.
if [ "${SKIP_SEEDS_ON_DEPLOY:-false}" = "true" ]; then
  echo "⏭  Skipping db:seed (SKIP_SEEDS_ON_DEPLOY=true)"
else
  log "🌱 Seeding"
  optional "seeding" rails db:seed
fi

# ── Instrument master ───────────────────────────────────────────────────────
# Large downloads from DhanHQ. Opt-in, and never fatal: the app boots without
# them and both tasks can be re-run from the Render shell.
if [ "${IMPORT_INSTRUMENTS_ON_DEPLOY:-false}" = "true" ]; then
  log "📊 Importing instruments"
  optional "instrument import" rails import:instruments
  optional "MIS detail import" rails import:mis_details
else
  echo "⏭  Skipping instrument imports (set IMPORT_INSTRUMENTS_ON_DEPLOY=true)"
fi

log "✅ Build complete"
