module PortfolioInsights
  class DailyReporterJob < ApplicationJob
    queue_as :default

    def perform
      holdings = Dhanhq::API::Holdings.fetch
      PortfolioInsights::Analyzer.call(dhan_holdings: holdings)
    end
  end
end
