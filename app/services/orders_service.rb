class OrdersService
  def self.fetch_orders
    Dhanhq::API::Orders.list
  rescue StandardError => e
    Rails.logger.error("Error fetching orders: #{e.message}")
    { error: e.message }
  end

  def self.fetch_trades
    Dhanhq::API::Orders.trades
  rescue StandardError => e
    Rails.logger.error("Error fetching trades: #{e.message}")
    { error: e.message }
  end
end
