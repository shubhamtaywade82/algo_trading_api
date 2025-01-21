# frozen_string_literal: true

namespace :jobs do
  desc 'Schedule periodic jobs for OrderManager and PositionManager'
  task schedule: :environment do
    OrderManagerJob.set(queue: 'order_manager', wait: 5.minutes).perform_later
    PositionManagerJob.set(queue: 'position_manager', wait: 10.minutes).perform_later

    puts 'Jobs have been scheduled.'
  end
end
