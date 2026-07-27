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

# Some database failures are settled before the first packet: a certificate
# that cannot verify, or a password the server rejects, fails identically on
# every attempt. Retrying those spends 30 seconds and buries the real error
# under four copies of itself, so they abort straight away with the setting to
# change. Anything else is treated as transient and retried.
explain_db_failure() {
  local log_file=$1

  if grep -Eq 'certificate verify failed|root certificate file|sslmode|SSL error' "$log_file"; then
    cat <<'EOF'
  The TLS handshake with the database failed.

  config/database.yml encrypts the connection without verifying the server
  certificate unless DATABASE_SSLMODE says otherwise. If it is set to verify-ca
  or verify-full, either drop it or set DATABASE_SSLROOTCERT to the CA bundle
  your provider publishes — a managed instance reached over a private network
  is signed by the provider's own CA and answers on an address its certificate
  does not name, so neither check can pass against the system trust store.
EOF
    return 0
  fi

  if grep -Eq 'password authentication failed|role .* does not exist' "$log_file"; then
    echo '  The database rejected the credentials in DATABASE_URL.'
    return 0
  fi

  return 1
}

# Runs a command, retrying with exponential backoff. Used for anything that
# touches the database: a managed instance can refuse connections for the first
# few seconds after it wakes, which is not a reason to fail a deploy.
retry() {
  local attempts=$1 description=$2; shift 2
  local attempt=1 delay=2 log_file hint
  log_file=$(mktemp)

  until "$@" 2>&1 | tee "$log_file"; do
    if hint=$(explain_db_failure "$log_file"); then
      printf '\033[31m✖ %s failed for a reason retrying cannot fix\033[0m\n' "$description"
      printf '%s\n' "$hint"
      rm -f "$log_file"
      return 1
    fi

    if (( attempt >= attempts )); then
      printf '\033[31m✖ %s failed after %d attempts\033[0m\n' "$description" "$attempts"
      rm -f "$log_file"
      return 1
    fi
    warn "$description failed (attempt ${attempt}/${attempts}); retrying in ${delay}s"
    sleep "$delay"
    attempt=$(( attempt + 1 ))
    delay=$(( delay * 2 ))
  done

  rm -f "$log_file"
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
#
# The seed step above has already loaded the index segment (NIFTY, BANKNIFTY,
# SENSEX, INDIA VIX and the rest of IDX_I) from db/seeds/index_instruments.csv,
# so the analysis commands resolve their symbols with the import skipped. Equities
# and derivatives still need it.
if [ "${IMPORT_INSTRUMENTS_ON_DEPLOY:-false}" = "true" ]; then
  log "📊 Importing instruments"
  optional "instrument import" rails import:instruments
  optional "MIS detail import" rails import:mis_details
else
  echo "⏭  Skipping instrument imports (set IMPORT_INSTRUMENTS_ON_DEPLOY=true)"
fi

log "✅ Build complete"
