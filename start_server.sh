#!/bin/bash
echo "Updating cron jobs..."
bundle exec whenever --update-crontab
echo "Starting Rails server..."
bundle exec rake jobs:work
rails server
