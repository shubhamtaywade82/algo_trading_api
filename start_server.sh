#!/bin/bash
set -e  # Exit on failure

echo "⏳ Updating cron jobs for local environment..."
bundle exec whenever --update-crontab || echo "Skipping whenever."

echo "📡 Starting background job worker..."
bundle exec rake jobs:work &

echo "🚀 Starting Rails server..."
exec bundle exec rails server
