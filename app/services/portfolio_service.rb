# frozen_string_literal: true

class PortfolioService
  def self.fetch_holdings
    DhanHQ::Models::Holding.all.map(&:attributes)
  rescue StandardError => e
    Rails.logger.error("Error fetching holdings: #{e.message}")
    { error: e.message }
  end

  def self.fetch_positions
    DhanHQ::Models::Position.all.map(&:attributes)
  rescue StandardError => e
    Rails.logger.error("Error fetching positions: #{e.message}")
    { error: e.message }
  end
end
