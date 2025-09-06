# frozen_string_literal: true

namespace :jobs do
  desc 'Schedule periodic jobs for OrderManager and PositionManager'
  task schedule: :environment do
    # NOTE: OrderManagerJob and PositionManagerJob classes do not exist
    # Use the service classes directly instead:
    # - Orders::Manager for order management
    # - Positions::Manager for position management

    puts 'No jobs to schedule - use service classes directly instead.'
  end
end
