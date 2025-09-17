#!/usr/bin/env bash
# exit on error
set -o errexit

# Install gems
echo "📦 Installing dependencies..."
bundle install

#bundle exec rails g solid_cache:install

# Run database migrations
# echo "🛠 Running migrations..."
# bundle exec rails db:migrate

# Run whenever to update cron jobs (only relevant if using cron-based jobs)
# Note: Render does NOT support system-level cron, so use a worker instead.
# echo "⏳ Updating cron jobs..."
# bundle exec whenever --update-crontab || echo "Skipping whenever (not supported on Render)."

# Uncomment below only if needed for fresh deployments
# echo "🌱 Seeding database..."
# bundle exec rails db:seed

# Optional data imports (comment if not needed)
echo "📊 Importing instruments..."
# bundle exec rails import:instruments
# bundle exec rails import:mis_details

# echo "🔄 Updating levels..."
# bundle exec rails levels:update