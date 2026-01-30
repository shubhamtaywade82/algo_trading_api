#!/usr/bin/env bash
# exit on error
set -o errexit

# Install gems
echo "📦 Installing dependencies..."
bundle install

# Run database migrations (use bin/rails to avoid gem binstubs that check bin/bundle on Render)
echo "🛠 Running migrations..."
ruby bin/rails db:migrate

# Run whenever to update cron jobs (only relevant if using cron-based jobs)
# Note: Render does NOT support system-level cron, so use a worker instead.
# echo "⏳ Updating cron jobs..."
# bundle exec whenever --update-crontab || echo "Skipping whenever (not supported on Render)."

# Only run seeds when RUN_SEEDS_ON_DEPLOY=true (e.g. first deploy or after seed changes)
if [ "${RUN_SEEDS_ON_DEPLOY}" = "true" ]; then
  echo "🌱 Seeding database..."
  ruby bin/rails db:seed
else
  echo "⏭ Skipping db:seed (set RUN_SEEDS_ON_DEPLOY=true to run)"
fi

# Only run instrument/MIS imports when IMPORT_INSTRUMENTS_ON_DEPLOY=true (e.g. first deploy)
if [ "${IMPORT_INSTRUMENTS_ON_DEPLOY}" = "true" ]; then
  echo "📊 Importing instruments..."
  ruby bin/rails import:instruments
  ruby bin/rails import:mis_details
else
  echo "⏭ Skipping instrument imports (set IMPORT_INSTRUMENTS_ON_DEPLOY=true to run)"
fi

echo "COMPLETED BUILD"