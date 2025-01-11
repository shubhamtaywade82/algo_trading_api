# frozen_string_literal: true

class PortfolioService
  def self.fetch_holdings
    Dhanhq::API::Portfolio.holdings
  rescue StandardError => e
    Rails.logger.error("Error fetching holdings: #{e.message}")
    { error: e.message }
  end

  def self.fetch_positions
    Dhanhq::API::Portfolio.positions
  rescue StandardError => e
    Rails.logger.error("Error fetching positions: #{e.message}")
    { error: e.message }
  end
end
