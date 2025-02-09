# frozen_string_literal: true

# Use this file to easily define all of your cron jobs.
#
# It's helpful, but not entirely necessary to understand cron before proceeding.
# http://en.wikipedia.org/wiki/Cron

# Example:
#
# set :output, "/path/to/my/cron_log.log"
#
# every 2.hours do
#   command "/usr/bin/some_great_command"
#   runner "MyModel.some_method"
#   rake "some:great:rake:task"
# end
#
# every 4.days do
#   runner "AnotherModel.prune_old_records"
# end

# Learn more: http://github.com/javan/whenever

set :environment, ENV['RAILS_ENV'] || 'development'
set :output, 'log/cron.log'

# 📌 Orders Management (Monitor Pending & Open Orders)
every 1.minute do
  runner 'Managers::Orders.call'
end

# 📌 Positions Management (Monitor Positions & Adjust Stop-Loss)
every 1.minute do
  runner 'Managers::Positions.call'
end

# 📌 Holdings Management (Check for Profit Exits)
every 5.minutes do
  runner 'Managers::Holdings.call'
end

# 📌 Adjust Stop-Loss for Open Positions
every 2.minutes do
  runner 'Managers::Positions::StopLoss.call'
end

# 📌 Adjust Stop-Loss for Open Orders
every 1.minute do
  runner 'Managers::Orders::StopLoss.call'
end

# 📌 Process Delayed Job Tasks
every 1.minute do
  rake 'jobs:workoff'
end

# 📌 Weekly Cleanup Task (E.g., Level Updates)
every :sunday, at: '2:00 am' do
  runner 'LevelsUpdateJob.perform_later'
end
