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

# Uncomment below only if needed for fresh deployments
echo "🌱 Seeding database..."
ruby bin/rails db:seed

# Optional data imports (comment if not needed)
echo "📊 Importing instruments..."
ruby bin/rails import:instruments
ruby bin/rails import:mis_details

# echo "🔄 Updating levels..."
# bundle exec rails levels:update
echo "COMPLETED BUILD"