# frozen_string_literal: true

namespace :order_management do
  desc 'Process pending orders'
  task process_pending_orders: :environment do
    Order.where(status: 'PENDING').find_each do |order|
      # Update order statuses or retry placements
    end
  end
end
