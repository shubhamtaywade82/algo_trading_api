# frozen_string_literal: true

# General AI service facade that provides access to various AI capabilities
class Ai < ApplicationService
  # Market analysis
  def self.analyze_market(symbol, **options)
    Market::AnalysisService.call(symbol, **options)
  end

  # Portfolio analysis
  def self.analyze_portfolio(holdings, **options)
    PortfolioInsights::Analyzer.call(
      dhan_holdings: holdings,
      **options
    )
  end

  # Position analysis
  def self.analyze_positions(positions, **options)
    PositionInsights::Analyzer.call(
      dhan_positions: positions,
      **options
    )
  end

  # Institutional portfolio analysis
  def self.analyze_institutional(holdings, **options)
    PortfolioInsights::InstitutionalAnalyzer.call(
      dhan_holdings: holdings,
      **options
    )
  end

  # Direct chat with OpenAI
  def self.chat(prompt, **options)
    Openai::ChatRouter.ask!(prompt, **options)
  end

  # Quick market analysis for common symbols
  def self.nifty_analysis(candle: '15m')
    analyze_market('NIFTY', candle: candle)
  end

  def self.banknifty_analysis(candle: '15m')
    analyze_market('BANKNIFTY', candle: candle)
  end

  # Quick portfolio analysis from DhanHQ data
  def self.quick_portfolio_analysis
    holdings = Dhanhq::API::Portfolio.holdings
    analyze_portfolio(holdings, interactive: true)
  end

  # Quick position analysis from DhanHQ data
  def self.quick_position_analysis
    positions = Dhanhq::API::Portfolio.positions
    analyze_positions(positions, interactive: true)
  end
end
