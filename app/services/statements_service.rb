class StatementsService
  def self.fetch_ledger(from_date, to_date)
    Dhanhq::API::Statements.ledger(from_date: from_date, to_date: to_date)
  rescue StandardError => e
    Rails.logger.error("Error fetching ledger: #{e.message}")
    { error: e.message }
  end

  def self.fetch_trade_history(from_date, to_date, page = 0)
    Dhanhq::API::Statements.trade_history(from_date: from_date, to_date: to_date, page: page)
  rescue StandardError => e
    Rails.logger.error("Error fetching trade history: #{e.message}")
    { error: e.message }
  end
end
