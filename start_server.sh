#!/bin/bash
set -e  # Exit on error

echo "🔄 Updating crontab using whenever..."
bundle exec whenever --update-crontab || echo "⚠️ Failed to update crontab."

echo "📆 Verifying cron is running..."
# service cron start || echo "⚠️ Unable to start cron service (ensure cron is installed and running)."

echo "🧵 Starting delayed job worker (if used)..."
bundle exec rake jobs:work &

echo "🚀 Launching Rails server..."
exec bundle exec rails server