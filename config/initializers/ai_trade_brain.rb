# frozen_string_literal: true

# AI::TradeBrain — public façade for the AI agent cluster.
#
# Defined here so it is not affected by Rails' code reloader in development.
# Runners are loaded explicitly so AI::Runners is available (Zeitwerk would not
# autoload them into this AI module because it is defined in this initializer).
module AI
  module TradeBrain
    module_function

    def analyze(symbol, candle: '15m', context: nil)
      input = "Analyze #{symbol} market structure and options flow for the current session. " \
              "Use #{candle} candle data."
      result = AI::Runners::MarketRunner.run(input, context: context || {})
      Rails.logger.info "[TradeBrain] analyze(#{symbol}) complete"
      result
    end

    def propose(symbol:, direction: nil, context: nil)
      dir_hint = direction ? " Preferred direction: #{direction}." : ''
      input    = "Generate a concrete options trade setup for #{symbol}.#{dir_hint} " \
                 'Include specific strike, entry, stop-loss, and target.'
      result   = AI::Runners::TradeRunner.run(input, context: context || {})
      proposal = AI::Runners::TradeRunner.extract_proposal(result.output)
      Rails.logger.info "[TradeBrain] propose(#{symbol}) → proposal=#{proposal.inspect}"
      {
        result:     result,
        output:     result.output,
        context:    result.context,
        proposal:   proposal,
        validation: proposal ? Strategy::Validator.validate(proposal) : nil
      }
    end

    def review_positions(context: nil)
      result = AI::Runners::OperatorRunner.run(
        'Review all current open positions. Assess P&L, risk level, ' \
        'and flag any positions that should be considered for exit.',
        context: context || {}
      )
      Rails.logger.info "[TradeBrain] review_positions → #{result.output.to_s.slice(0, 80)}..."
      result
    end

    def ask(question, context: nil)
      result = AI::Runners::OperatorRunner.run(question, context: context || {})
      Rails.logger.info "[TradeBrain] ask → #{result.output.to_s.slice(0, 80)}..."
      result
    end

    def quick_analysis(symbol)
      agent  = AI::Agents::MarketStructureAgent.build
      runner = ::Agents::Runner.with_agents(agent)
      runner.run("Quick market structure analysis for #{symbol}. Use 15m candles.")
    end

    def session_report(symbol)
      analysis     = analyze(symbol)
      positions    = review_positions
      trade_result = propose(symbol: symbol)
      {
        symbol:     symbol,
        timestamp:  Time.current.iso8601,
        analysis:   analysis.output,
        positions:  positions.output,
        proposal:   trade_result[:proposal],
        validation: trade_result[:validation],
        context:    trade_result.dig(:result, :context)
      }
    end
  end
end

# Load runner files into AI so AI::Runners::* is available (initializer defines AI first,
# so Zeitwerk does not autoload app/ai into this namespace).
# Load tools and agents first (runners depend on AI::Agents::*).
ai_root = Rails.root.join('app/ai')
%w[tools agents runners].each do |subdir|
  Dir[ai_root.join(subdir, '*.rb')].sort.each { |f| load f }
end
