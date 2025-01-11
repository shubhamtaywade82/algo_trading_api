# frozen_string_literal: true

namespace :positions do
  desc 'Manage stop losses for naked positions'
  task manage_stop_losses: :environment do
    Positions::PositionManager.call
  end

  desc 'Trail stop losses'
  task trail_stop_losses: :environment do
    Positions::PositionManager.new.trail_stop_losses
  end

  desc 'Set take profit orders'
  task set_take_profit_orders: :environment do
    Positions::PositionManager.new.set_take_profit_orders
  end
end

namespace :orders do
  desc 'Process market orders'
  task process_market_orders: :environment do
    Orders::StopLossManager.new.process_orders
  end
end
