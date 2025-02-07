#!/usr/bin/env bash
# exit on error
set -o errexit
# Install gems
bundle install
rails db:migrate

rails db:seed
rails import:instruments
rails import:mis_details
# rails levels:update