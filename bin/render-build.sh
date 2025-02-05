#!/usr/bin/env bash
# exit on error
set -o errexit

bundle install

# Migrate database
rails db:migrate