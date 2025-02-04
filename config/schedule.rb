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
# every :sunday, at: '2:00 am' do
#   runner 'LevelsUpdateJob.perform_later'
# end

every 1.minute do
  runner 'Managers::Orders::Processor.call'
end

every 1.minute do
  runner 'Managers::Positions.call'
end
# # Process Delayed Job tasks every minute
# every 1.minute do
#   rake 'jobs:workoff'
# end

# every 1.minute do
#   runner 'OrderManagerJob.perform_later'
# end

# every 5.minutes do
#   runner 'PositionsManagerJob.perform_later'
# end

# # Stop-loss adjustments for positions
# every 2.minutes do
#   runner 'AdjustStopLossManagerJob.perform_later'
# end

# # Stop-loss adjustments for orders
# every 1.minute do
#   runner 'StopLossManagerJob.perform_later'
# end
