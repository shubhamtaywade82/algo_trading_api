#!/bin/bash
echo "Updating cron jobs..."
bundle exec whenever --update-crontab
echo "Starting Rails server..."
sudo service cron start
rails server
