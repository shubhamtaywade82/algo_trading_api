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
  # DhanHQ SDK AI layer (gem >= 3.2.1)
  # -------------------------------------------------------------------------
  #
  # `DhanHQ::AI` was unreachable before 3.2.1 — the Zeitwerk inflector had no
  # `ai -> AI` acronym, so a bare `require "dhan_hq"` raised NameError for both
  # spellings. These wrappers are safe to call from 3.2.1 onward.

  # Broker-aware system prompt for an LLM that will call DhanHQ tools.
  # @param capabilities [Array<String>, nil]
  def self.system_prompt(capabilities: nil)
    capabilities ? DhanHQ::AI::PromptHelpers.system_prompt(capabilities: capabilities)
                 : DhanHQ::AI::PromptHelpers.system_prompt
  end

  # Renders holdings/positions/funds into a prompt-ready portfolio summary.
  # Each collection is Array()-wrapped by the SDK, so a failed fetch renders an
  # empty section rather than raising mid-prompt.
  def self.portfolio_prompt(holdings: nil, positions: nil, funds: nil)
    DhanHQ::AI::PromptHelpers.portfolio_summary(
      holdings: holdings || DhanHQ::Models::Holding.all,
      positions: positions || DhanHQ::Models::Position.all,
      funds: funds || DhanHQ::Models::Funds.fetch
    )
  rescue StandardError => e
    Rails.logger.error("[Ai] portfolio_prompt failed: #{e.class} - #{e.message}")
    nil
  end

  # Prompt-ready risk report across open positions.
  def self.risk_prompt(positions: nil, risk_params: nil)
    positions ||= DhanHQ::Models::Position.all
    if risk_params
      DhanHQ::AI::PromptHelpers.risk_report(positions: positions, risk_params: risk_params)
    else
      DhanHQ::AI::PromptHelpers.risk_report(positions: positions)
    end
  rescue StandardError => e
    Rails.logger.error("[Ai] risk_prompt failed: #{e.class} - #{e.message}")
    nil
  end

  # Human-readable confirmation of an order payload, for a
  # propose-then-confirm flow. Renders only; places nothing.
  def self.order_confirmation(order_params)
    DhanHQ::AI::PromptHelpers.order_confirmation(order_params)
  end

  # Account/market context hash the SDK assembles for an LLM turn.
  def self.broker_context
    DhanHQ::AI::ContextBuilder.build
  rescue StandardError => e
    Rails.logger.error("[Ai] broker_context failed: #{e.class} - #{e.message}")
    {}
  end

  # -------------------------------------------------------------------------
  # SDK skills (gated — see Dhan::SkillsService)
  # -------------------------------------------------------------------------

  # @return [Array<Hash>] available skills with risk/scope and permitted flag
  def self.skills
    Dhan::SkillsService.catalogue
  end

  # Runs an SDK skill. Destructive skills require PLACE_ORDER + LIVE_TRADING.
  def self.run_skill(name, args = {})
    Dhan::SkillsService.call(name, args, source: 'Ai.run_skill')
  end

  # -------------------------------------------------------------------------
  # Option analytics (gem >= 3.2.0)
  # -------------------------------------------------------------------------

  # Black-Scholes greeks for a single option leg.
  #
  # @param time_to_expiry [Float] in years
  # @param volatility [Float] as a decimal, e.g. 0.14 for 14% IV
  # @param risk_free_rate [Float] decimal; defaults to the RBI repo-ish 6.5%
  # @param option_type [Symbol, String] :call or :put
  def self.greeks(spot:, strike:, time_to_expiry:, volatility:, risk_free_rate: 0.065, option_type: :call)
    DhanHQ::OptionAnalytics::BlackScholes.greeks(
      spot: spot, strike: strike, time_to_expiry: time_to_expiry,
      risk_free_rate: risk_free_rate, volatility: volatility, option_type: option_type
    )
  end

  # Max-pain strike for an option chain in the SDK's 3.x shape.
  def self.max_pain(option_chain)
    DhanHQ::OptionAnalytics::MaxPain.calculate(option_chain)
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
