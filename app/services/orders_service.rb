# frozen_string_literal: true

class OrdersService
  def self.fetch_orders
    retries ||= 0
    Dhanhq::API::Orders.list
  rescue StandardError => e
    ErrorHandler.handle_error(
      context: 'Fetching orders',
      exception: e,
      retries: retries + 1,
      retry_logic: -> { fetch_orders }
    )
  end
end
