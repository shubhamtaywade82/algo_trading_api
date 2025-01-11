# frozen_string_literal: true

class FundsService
  def self.fetch_funds
    Dhanhq::API::Funds.balance
  rescue StandardError => e
    Rails.logger.error("Error fetching funds: #{e.message}")
    { error: e.message }
  end
end
