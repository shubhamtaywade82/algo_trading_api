#!/usr/bin/env bash
# exit on error
set -o errexit
# Install gems
bundle install

# On the free plan, there's NO "pre-deploy command," so run migrations here:
bundle exec rails db:migrate
# If you want to run seeds on every deploy, include:
bundle exec rails db:seed

# If you have custom rake tasks for data import:
# bundle exec rails import:instruments
# bundle exec rails import:mis_details