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

  # -------------------------------------------------------------------------
  # AI Agent cluster (orchestrated multi-agent intelligence layer)
  # -------------------------------------------------------------------------

  # Full market analysis via agent pipeline (structure + options flow + synthesis).
  # @param symbol [String]  e.g. "NIFTY"
  # @param candle [String]  e.g. "15m"
  def self.agent_analyze(symbol, candle: '15m')
    AI::TradeBrain.analyze(symbol, candle: candle)
  end

  # Generate an AI trade proposal for a symbol via the full agent pipeline.
  # The returned proposal must be validated by Strategy::Validator before execution.
  # @param symbol    [String]
  # @param direction [String, nil] optional: "CE" or "PE"
  def self.agent_propose(symbol, direction: nil)
    AI::TradeBrain.propose(symbol: symbol, direction: direction)
  end

  # Answer an operational/debugging question about the trading system.
  # @param question [String]  free-form natural language question
  def self.agent_ask(question)
    AI::TradeBrain.ask(question)
  end

  # Shortcut: full NIFTY session report (analysis + positions + proposal).
  def self.nifty_session_report
    AI::TradeBrain.session_report('NIFTY')
  end

  # Shortcut: full BANKNIFTY session report.
  def self.banknifty_session_report
    AI::TradeBrain.session_report('BANKNIFTY')
  end
end
