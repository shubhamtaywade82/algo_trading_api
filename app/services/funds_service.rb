# frozen_string_literal: true

class FundsService
  def self.fetch_funds
    retries ||= 0
    Dhanhq::API::Funds.balance
  rescue StandardError => e
    ErrorHandler.handle_error(
      context: 'Fetching funds',
      exception: e,
      retries: retries + 1,
      retry_logic: -> { fetch_funds }
    )
  end
end
