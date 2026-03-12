# frozen_string_literal: true

module AI
  module Tools
    # Fetches and analyzes the option chain for an index via existing ChainAnalyzer.
    class OptionChainTool < BaseTool
      TOOL_NAME   = 'get_option_chain'
      DESCRIPTION = 'Fetch and analyze the option chain for an NSE index (NIFTY, BANKNIFTY, FINNIFTY). Returns IV rank, ATM strike data, PCR, and recommended strikes.'
      PARAMETERS  = {
        type: 'object',
        properties: {
          symbol: {
            type: 'string',
            description: 'Index symbol: NIFTY, BANKNIFTY, or FINNIFTY'
          },
          expiry: {
            type: 'string',
            description: 'Expiry date YYYY-MM-DD (optional, defaults to nearest)'
          },
          signal_type: {
            type: 'string',
            description: 'Signal direction for strike recommendation: ce (bullish), pe (bearish)',
            enum: %w[ce pe]
          }
        },
        required: %w[symbol]
      }.freeze

      def perform(args)
        symbol      = args['symbol'].to_s.upcase
        expiry      = args['expiry']
        signal_type = (args['signal_type'] || 'ce').to_sym

        instrument = Instrument.segment_index.find_by(underlying_symbol: symbol)
        return { error: "Index instrument not found: #{symbol}" } unless instrument

        expiry ||= instrument.expiry_list&.first
        return { error: "No expiry available for #{symbol}" } unless expiry

        chain = instrument.fetch_option_chain(expiry)
        return { error: 'Option chain unavailable' } unless chain

        ltp      = instrument.ltp.to_f
        iv_rank  = Option::ChainAnalyzer.estimate_iv_rank(chain)

        historical = Option::HistoricalDataFetcher.for_strategy(instrument, strategy_type: 'intraday')
        analyzer   = Option::ChainAnalyzer.new(
          chain,
          expiry:           expiry,
          underlying_spot:  ltp,
          iv_rank:          iv_rank,
          historical_data:  historical
        )

        analysis = analyzer.analyze(strategy_type: 'intraday', signal_type: signal_type)
        sentiment = Market::SentimentAnalysis.call(chain)

        {
          symbol:          symbol,
          expiry:          expiry,
          ltp:             ltp.round(2),
          iv_rank:         iv_rank&.round(2),
          pcr:             sentiment[:pcr]&.round(3),
          sentiment:       sentiment[:sentiment],
          best_strike:     analysis[:best_strike],
          top_strikes:     analysis[:strikes]&.first(3),
          trend:           analysis[:trend],
          chain_summary:   summarize_chain(chain, ltp)
        }
      rescue StandardError => e
        { error: e.message }
      end

      private

      def summarize_chain(chain, ltp)
        atm_strike = (ltp / 50.0).round * 50

        strikes = chain.select { |row| (row['strikePrice'].to_f - atm_strike).abs <= 200 }
        strikes.first(5).map do |row|
          {
            strike:  row['strikePrice'].to_f,
            ce_ltp:  row.dig('callOption', 'last_price').to_f.round(2),
            pe_ltp:  row.dig('putOption',  'last_price').to_f.round(2),
            ce_oi:   row.dig('callOption', 'oi').to_i,
            pe_oi:   row.dig('putOption',  'oi').to_i,
            ce_iv:   row.dig('callOption', 'implied_volatility').to_f.round(2),
            pe_iv:   row.dig('putOption',  'implied_volatility').to_f.round(2)
          }
        end
      end
    end
  end
end
